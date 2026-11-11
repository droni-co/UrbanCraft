import vine from '@vinejs/vine'

/**
 * Shared rules for email and password.
 */
const email = () => vine.string().email().maxLength(254)
const password = () => vine.string().minLength(8).maxLength(32)

/**
 * Validator to use when performing self-signup
 */
export const signupValidator = vine.create({
  fullName: vine.string().nullable(),
  email: email().unique({ table: 'users', column: 'email' }),
  password: password(),
  passwordConfirmation: password().sameAs('password'),
})

/**
 * Perfil del jugador (cada campo es opcional):
 * - nickname: 3–20 letras (con tildes), números o guion bajo.
 * - skin: nombre del personaje (PNG en apps/game/assets/art/characters, sin
 *   extensión). El servidor no conoce el arte: solo valida el formato y el
 *   juego usa el personaje por defecto si no lo tiene.
 */
export const updateProfileValidator = vine.create({
  nickname: vine
    .string()
    .trim()
    .minLength(3)
    .maxLength(20)
    .regex(/^[\p{L}\p{N}_]+$/u)
    .optional(),
  skin: vine
    .string()
    .trim()
    .maxLength(32)
    .regex(/^[a-z0-9_-]+$/)
    .optional(),
})

/**
 * Validator to use before validating user credentials
 * during login
 */
export const loginValidator = vine.create({
  email: email(),
  password: vine.string(),
})
