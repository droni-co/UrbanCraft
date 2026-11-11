import type { ApplicationService } from '@adonisjs/core/types'
import type { OAuthConfig } from '#config/oauth'
import { GoogleOAuthClient, HttpGoogleOAuthClient } from '#auth/google_client'
import { OAuthLoginService } from '#services/oauth_login_service'

export default class OAuthProvider {
  constructor(protected app: ApplicationService) {}

  register() {
    const config = () => this.app.config.get<OAuthConfig>('oauth')

    this.app.container.singleton(
      GoogleOAuthClient,
      () => new HttpGoogleOAuthClient(config().google)
    )
    this.app.container.singleton(
      OAuthLoginService,
      async (resolver) => new OAuthLoginService(config(), await resolver.make(GoogleOAuthClient))
    )
  }
}
