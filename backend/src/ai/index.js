'use strict';

const config = require('../config');
const logger = require('../utils/logger');
const localProvider = require('./localProvider');
const { makeCloudProvider } = require('./cloudProviders');

/**
 * AI provider factory. `AI_PROVIDER` selects the implementation without any
 * change to calling code. If the configured cloud provider is not usable
 * (missing key or external transfer not explicitly allowed) the local provider
 * is used and the substitution is reported honestly in the response.
 */

let cached = null;

function getProvider() {
  if (cached) return cached;
  if (config.ai.provider === 'openai' || config.ai.provider === 'anthropic') {
    const cloud = makeCloudProvider(config.ai.provider);
    if (cloud.available) {
      cached = cloud;
      return cached;
    }
    logger.warn('AI provider "%s" unavailable (%s). Falling back to local provider.', config.ai.provider, cloud.reason);
  }
  cached = localProvider;
  return cached;
}

/** Describe the active provider for startup logging and a health endpoint. */
function describe() {
  const p = getProvider();
  return {
    configured: config.ai.provider,
    active: p.name,
    model: p.model,
    external: p.name !== 'local',
    allowExternalDataTransfer: config.ai.allowExternal,
    fallbackReason: p === localProvider && config.ai.provider !== 'local'
      ? `Configured provider "${config.ai.provider}" is not available; using the local offline provider.`
      : undefined,
  };
}

function _reset() { cached = null; }

module.exports = { getProvider, describe, _reset };
