// Voz con amigos en la versión web (WebRTC directo entre navegadores).
//
// Lo carga el autoload Voice (scripts/autoload/voice.gd) con JavaScriptBridge.
// Godot decide CON QUIÉN conectarse (el servidor le avisa qué amigos están en
// la voz) y reenvía la señalización por el WebSocket del juego; aquí se hace
// todo lo de audio: micrófono (con cancelación de eco y supresión de ruido del
// navegador), una RTCPeerConnection por amigo, reproducción y detección de
// quién está hablando.
//
// Eventos hacia Godot (JSON por el callback de setHandler):
//   { e: 'mic', ok, error? }        resultado de pedir el micrófono
//   { e: 'signal', to, k, d }       señalización para mandar a un amigo
//   { e: 'state', id, s }           estado de la conexión (connecting, connected, failed…)
//   { e: 'speaking', id, on }       un amigo empezó o dejó de hablar
//   { e: 'tx', on }                 tu micrófono empezó o dejó de transmitir
;(() => {
  if (window.UCVoice) return

  const SPEAK_LEVEL = 0.02 // RMS a partir del cual se considera voz
  const OPEN_MIC_LEVEL = 0.03 // micrófono abierto: umbral para transmitir
  const HANGOVER_MS = 400 // sigue "hablando" un poco tras la última sílaba

  const peers = new Map() // id -> { pc, audio, analyser, muted, speaking, lastVoice, pendingIce }
  let handler = null
  let iceServers = []
  let mic = null // MediaStream original del micrófono (para medir el nivel)
  let send = null // MediaStream con la pista clonada que se envía (se activa o no)
  let ctx = null
  let micAnalyser = null
  let meter = null
  let talking = false // pulsar para hablar
  let openMic = false
  let tx = false
  let micLastVoice = 0

  const emit = (event) => {
    if (handler) handler(JSON.stringify(event))
  }

  function level(analyser) {
    const data = new Float32Array(analyser.fftSize)
    analyser.getFloatTimeDomainData(data)
    let sum = 0
    for (const v of data) sum += v * v
    return Math.sqrt(sum / data.length)
  }

  function makeAnalyser(stream) {
    const analyser = ctx.createAnalyser()
    analyser.fftSize = 512
    ctx.createMediaStreamSource(stream).connect(analyser)
    return analyser
  }

  function setTx(on) {
    if (send) for (const t of send.getAudioTracks()) t.enabled = on
    if (on !== tx) {
      tx = on
      emit({ e: 'tx', on })
    }
  }

  // Cada 100 ms: quién habla y, con micrófono abierto, si se transmite.
  function tick() {
    const now = performance.now()
    if (micAnalyser) {
      if (level(micAnalyser) > OPEN_MIC_LEVEL) micLastVoice = now
      setTx(talking || (openMic && now - micLastVoice < HANGOVER_MS))
    }
    for (const [id, p] of peers) {
      if (!p.analyser) continue
      if (level(p.analyser) > SPEAK_LEVEL) p.lastVoice = now
      const speaking = !p.muted && now - p.lastVoice < HANGOVER_MS
      if (speaking !== p.speaking) {
        p.speaking = speaking
        emit({ e: 'speaking', id, on: speaking })
      }
    }
  }

  function closePeer(id) {
    const p = peers.get(id)
    if (!p) return
    peers.delete(id)
    p.pc.onicecandidate = p.pc.ontrack = p.pc.onconnectionstatechange = null
    p.pc.close()
    if (p.audio) {
      p.audio.srcObject = null
      p.audio.remove()
    }
  }

  function makePeer(id, initiator) {
    closePeer(id)
    const pc = new RTCPeerConnection({ iceServers })
    const p = { pc, audio: null, analyser: null, muted: false, speaking: false, lastVoice: 0, pendingIce: [] }
    peers.set(id, p)
    for (const track of send.getAudioTracks()) pc.addTrack(track, send)

    pc.onicecandidate = (e) => {
      if (e.candidate) emit({ e: 'signal', to: id, k: 'ice', d: JSON.stringify(e.candidate) })
    }
    pc.ontrack = (e) => {
      const stream = e.streams[0] || new MediaStream([e.track])
      if (!p.audio) {
        p.audio = document.createElement('audio')
        p.audio.autoplay = true
        p.audio.style.display = 'none'
        document.body.appendChild(p.audio)
      }
      p.audio.srcObject = stream
      p.audio.muted = p.muted
      p.audio.play().catch(() => {})
      p.analyser = makeAnalyser(stream)
    }
    pc.onconnectionstatechange = () => emit({ e: 'state', id, s: pc.connectionState })
    emit({ e: 'state', id, s: 'connecting' })

    if (initiator) {
      pc.createOffer()
        .then((offer) => pc.setLocalDescription(offer))
        .then(() => emit({ e: 'signal', to: id, k: 'offer', d: JSON.stringify(pc.localDescription) }))
        .catch(() => emit({ e: 'state', id, s: 'failed' }))
    }
    return p
  }

  async function flushIce(p) {
    for (const c of p.pendingIce.splice(0)) await p.pc.addIceCandidate(c).catch(() => {})
  }

  window.UCVoice = {
    supported: () => Boolean(navigator.mediaDevices?.getUserMedia && window.RTCPeerConnection),

    setHandler(fn) {
      handler = fn
    },

    /** Pide el micrófono. iceJson: servidores STUN/TURN (JSON, del servidor). */
    async start(iceJson) {
      try {
        iceServers = JSON.parse(iceJson || '[]')
      } catch {
        iceServers = []
      }
      if (mic) return emit({ e: 'mic', ok: true })
      try {
        mic = await navigator.mediaDevices.getUserMedia({
          audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true },
          video: false,
        })
      } catch (err) {
        return emit({ e: 'mic', ok: false, error: (err && err.name) || 'Error' })
      }
      send = new MediaStream(mic.getAudioTracks().map((t) => t.clone()))
      ctx = new (window.AudioContext || window.webkitAudioContext)()
      ctx.resume().catch(() => {})
      micAnalyser = makeAnalyser(mic)
      tx = true
      setTx(false)
      meter = setInterval(tick, 100)
      emit({ e: 'mic', ok: true })
    },

    /** Suelta el micrófono y corta con todos. */
    stop() {
      for (const id of [...peers.keys()]) closePeer(id)
      clearInterval(meter)
      meter = null
      for (const s of [mic, send]) if (s) for (const t of s.getTracks()) t.stop()
      mic = send = micAnalyser = null
      if (ctx) ctx.close().catch(() => {})
      ctx = null
      talking = false
      if (tx) {
        tx = false
        emit({ e: 'tx', on: false })
      }
    },

    /** Un amigo está en la voz: conectarse. Ofrece el de id menor. */
    addPeer(id, initiator) {
      // Si su oferta llegó antes que el aviso, la conexión ya existe.
      if (send && !peers.has(id)) makePeer(id, initiator)
    },

    removePeer(id) {
      closePeer(id)
    },

    removeAll() {
      for (const id of [...peers.keys()]) closePeer(id)
    },

    /** Señalización que llegó de un amigo. */
    async receive(from, kind, data) {
      if (!send) return
      let payload
      try {
        payload = JSON.parse(data)
      } catch {
        return
      }
      let p = peers.get(from)
      try {
        if (kind === 'offer') {
          if (!p || p.pc.signalingState !== 'stable') p = makePeer(from, false)
          await p.pc.setRemoteDescription(payload)
          await flushIce(p)
          const answer = await p.pc.createAnswer()
          await p.pc.setLocalDescription(answer)
          emit({ e: 'signal', to: from, k: 'answer', d: JSON.stringify(p.pc.localDescription) })
        } else if (kind === 'answer' && p) {
          await p.pc.setRemoteDescription(payload)
          await flushIce(p)
        } else if (kind === 'ice' && p) {
          if (p.pc.remoteDescription) await p.pc.addIceCandidate(payload).catch(() => {})
          else p.pendingIce.push(payload)
        }
      } catch {
        emit({ e: 'state', id: from, s: 'failed' })
      }
    },

    /** Pulsar para hablar. */
    setTalking(on) {
      talking = Boolean(on)
    },

    setOpenMic(on) {
      openMic = Boolean(on)
    },

    /** Estado para depurar desde la consola del navegador: UCVoice.debug() */
    debug() {
      return {
        ctx: ctx && ctx.state,
        tx,
        talking,
        openMic,
        mic: micAnalyser ? level(micAnalyser) : null,
        peers: [...peers].map(([id, p]) => ({
          id,
          state: p.pc.connectionState,
          ice: p.pc.iceConnectionState,
          muted: p.muted,
          speaking: p.speaking,
          level: p.analyser ? level(p.analyser) : null,
        })),
      }
    },

    setMuted(id, on) {
      const p = peers.get(id)
      if (!p) return
      p.muted = Boolean(on)
      if (p.audio) p.audio.muted = p.muted
    },
  }
})()
