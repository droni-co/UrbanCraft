import db from '@adonisjs/lucid/services/db'
import type { BBox } from '#map/geo'

/**
 * Acceso a datos del mapa. Usa SQL directo porque las tablas tienen columnas
 * bytea y geometry (PostGIS) que no aportan nada como modelos Lucid.
 *
 * La tabla osm_source_tiles funciona también como COLA DE TRABAJOS durable:
 * varios servidores pueden procesarla a la vez gracias a FOR UPDATE SKIP LOCKED,
 * y los trabajos sobreviven a reinicios.
 */

export type SourceTileStatus = 'queued' | 'fetching' | 'ready' | 'failed'

export interface SourceTileRow {
  id: number
  z: number
  x: number
  y: number
  status: SourceTileStatus
  attempts: number
  rasterizedVersion: number
  hasData: boolean
  /** Versión de los datos guardados (ver config/map.ts dataVersion). */
  dataVersion: number
  /** Segundos desde que un worker lo tomó (solo con status 'fetching'). */
  lockedSecondsAgo: number | null
}

export interface ClaimedJob extends SourceTileRow {}

export interface ChunkRow {
  data: Buffer
  etag: string
}

const envelope = 'ST_MakeEnvelope(?, ?, ?, ?, 4326)'
const bboxBindings = (b: BBox) => [b.west, b.south, b.east, b.north]

function toSourceTile(row: any): SourceTileRow {
  return {
    id: Number(row.id),
    z: row.z,
    x: row.x,
    y: row.y,
    status: row.status,
    attempts: row.attempts,
    rasterizedVersion: row.rasterized_version,
    hasData: row.has_data,
    dataVersion: row.data_version,
    lockedSecondsAgo: row.locked_seconds_ago === null ? null : Number(row.locked_seconds_ago),
  }
}

const SOURCE_COLUMNS =
  'id, z, x, y, status, attempts, rasterized_version, data_version, (data IS NOT NULL) AS has_data, ' +
  'EXTRACT(EPOCH FROM now() - locked_at) AS locked_seconds_ago'

export class MapRepository {
  async findChunk(z: number, x: number, y: number, version: number): Promise<ChunkRow | null> {
    const { rows } = await db.rawQuery(
      'SELECT data, etag FROM map_chunks WHERE z = ? AND x = ? AND y = ? AND generator_version = ?',
      [z, x, y, version]
    )
    return rows[0] ? { data: rows[0].data, etag: rows[0].etag } : null
  }

  async findSourceTile(z: number, x: number, y: number): Promise<SourceTileRow | null> {
    const { rows } = await db.rawQuery(
      `SELECT ${SOURCE_COLUMNS} FROM osm_source_tiles WHERE z = ? AND x = ? AND y = ?`,
      [z, x, y]
    )
    return rows[0] ? toSourceTile(rows[0]) : null
  }

  /** Encola un source tile si no existe. Devuelve true si lo creó. */
  async enqueueSourceTile(z: number, x: number, y: number, bounds: BBox): Promise<boolean> {
    const { rows } = await db.rawQuery(
      `INSERT INTO osm_source_tiles (z, x, y, status, bounds, created_at, updated_at)
       VALUES (?, ?, ?, 'queued', ${envelope}, now(), now())
       ON CONFLICT (z, x, y) DO NOTHING
       RETURNING id`,
      [z, x, y, ...bboxBindings(bounds)]
    )
    return rows.length > 0
  }

  /** Vuelve a encolar un tile listo (ej. nueva versión del generador) o fallido. */
  async requeue(id: number, resetAttempts = false): Promise<void> {
    await db.rawQuery(
      `UPDATE osm_source_tiles
       SET status = 'queued', next_attempt_at = now(), updated_at = now()
           ${resetAttempts ? ', attempts = 0, last_error = NULL' : ''}
       WHERE id = ? AND status IN ('ready', 'failed')`,
      [id]
    )
  }

  /** Descarta los datos OSM guardados y vuelve a encolar (para pedirlos de nuevo). */
  async requeueForRefetch(id: number): Promise<void> {
    await db.rawQuery(
      `UPDATE osm_source_tiles
       SET status = 'queued', data = NULL, attempts = 0, last_error = NULL,
           next_attempt_at = now(), updated_at = now()
       WHERE id = ? AND status IN ('ready', 'failed')`,
      [id]
    )
  }

  async countQueued(): Promise<number> {
    const { rows } = await db.rawQuery(
      "SELECT count(*)::int AS n FROM osm_source_tiles WHERE status IN ('queued', 'fetching')"
    )
    return rows[0].n
  }

  /** Cuántos trabajos en cola se procesan antes que este (el orden de claimNextJob). */
  async queueAhead(id: number): Promise<number> {
    const { rows } = await db.rawQuery(
      `SELECT count(*)::int AS n FROM osm_source_tiles o, osm_source_tiles t
       WHERE t.id = ? AND o.id <> t.id AND (
         o.status = 'fetching' OR
         (o.status = 'queued' AND (o.next_attempt_at, o.id) < (t.next_attempt_at, t.id))
       )`,
      [id]
    )
    return rows[0]?.n ?? 0
  }

  /** Toma el siguiente trabajo pendiente de forma atómica (seguro con varios workers). */
  async claimNextJob(lockTimeoutMs: number): Promise<ClaimedJob | null> {
    const { rows } = await db.rawQuery(
      `UPDATE osm_source_tiles SET status = 'fetching', locked_at = now(), updated_at = now()
       WHERE id = (
         SELECT id FROM osm_source_tiles
         WHERE (status = 'queued' AND next_attempt_at <= now())
            OR (status = 'fetching' AND locked_at < now() - (? * interval '1 millisecond'))
         ORDER BY next_attempt_at, id
         LIMIT 1
         FOR UPDATE SKIP LOCKED
       )
       RETURNING ${SOURCE_COLUMNS}`,
      [lockTimeoutMs]
    )
    return rows[0] ? toSourceTile(rows[0]) : null
  }

  async loadSourceData(id: number): Promise<Buffer | null> {
    const { rows } = await db.rawQuery('SELECT data FROM osm_source_tiles WHERE id = ?', [id])
    return rows[0]?.data ?? null
  }

  async saveSourceData(
    id: number,
    data: Buffer,
    meta: {
      provider: string
      osmTimestamp: string | null
      featureCount: number
      dataVersion: number
    }
  ): Promise<void> {
    await db.rawQuery(
      `UPDATE osm_source_tiles
       SET data = ?, provider = ?, osm_timestamp = ?, feature_count = ?, data_version = ?,
           fetched_at = now(), updated_at = now()
       WHERE id = ?`,
      [data, meta.provider, meta.osmTimestamp, meta.featureCount, meta.dataVersion, id]
    )
  }

  /** Guarda todos los chunks de un source tile y lo marca listo, en una transacción. */
  async saveChunksAndMarkReady(
    sourceTileId: number,
    version: number,
    chunks: Array<{ z: number; x: number; y: number; data: Buffer; etag: string; bounds: BBox }>
  ): Promise<void> {
    await db.transaction(async (trx) => {
      for (const c of chunks) {
        await trx.rawQuery(
          `INSERT INTO map_chunks (z, x, y, generator_version, source_tile_id, data, etag, byte_size, bounds, created_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ${envelope}, now())
           ON CONFLICT (z, x, y, generator_version)
           DO UPDATE SET data = EXCLUDED.data, etag = EXCLUDED.etag, byte_size = EXCLUDED.byte_size,
                         source_tile_id = EXCLUDED.source_tile_id`,
          [
            c.z,
            c.x,
            c.y,
            version,
            sourceTileId,
            c.data,
            c.etag,
            c.data.length,
            ...bboxBindings(c.bounds),
          ]
        )
      }
      await trx.rawQuery(
        `UPDATE osm_source_tiles
         SET status = 'ready', rasterized_version = ?, locked_at = NULL, last_error = NULL, updated_at = now()
         WHERE id = ?`,
        [version, sourceTileId]
      )
    })
  }

  async markFailure(id: number, error: string, retryInMs: number | null): Promise<void> {
    if (retryInMs === null) {
      await db.rawQuery(
        `UPDATE osm_source_tiles SET status = 'failed', locked_at = NULL, last_error = ?, updated_at = now() WHERE id = ?`,
        [error.slice(0, 1000), id]
      )
      return
    }
    await db.rawQuery(
      `UPDATE osm_source_tiles
       SET status = 'queued', locked_at = NULL, last_error = ?, attempts = attempts + 1,
           next_attempt_at = now() + (? * interval '1 millisecond'), updated_at = now()
       WHERE id = ?`,
      [error.slice(0, 1000), retryInMs, id]
    )
  }
}
