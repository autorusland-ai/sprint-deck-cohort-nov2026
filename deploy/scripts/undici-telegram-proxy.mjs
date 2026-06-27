// Двойной патч для маршрутизации api.telegram.org через локальный HTTPS proxy
// (Privoxy 8118 → Tor 9050). Остальной трафик — напрямую.
//
// Применение: NODE_OPTIONS="--import=/home/clawd/.openclaw/scripts/undici-telegram-proxy.mjs"
//
// Зачем: api.telegram.org заблокирован для прямого доступа с TimeWeb RU IP.
// openclaw использует ОДНОВРЕМЕННО:
//   1. node-fetch / undici (для встроенного fetch — gateway внутренние вызовы)
//   2. node-telegram-bot-api → классический https.request (для polling)
// Один патч не покрывает оба — патчим оба.

import { ProxyAgent, Agent, setGlobalDispatcher } from '/home/clawd/.openclaw/npm/node_modules/undici/index.js';
import { HttpsProxyAgent } from '/home/clawd/.openclaw/npm/node_modules/https-proxy-agent/dist/index.js';
import https from 'node:https';
import http from 'node:http';

const PROXY_URL = process.env.TELEGRAM_PROXY_URL || 'http://127.0.0.1:8118';
const PROXIED_HOSTS = new Set([
    'api.telegram.org',
    'core.telegram.org',
]);

// ─────── (1) undici (для fetch / node 24 встроенный) ───────
const directAgent = new Agent();
const undiciProxyAgent = new ProxyAgent({ uri: PROXY_URL });

class RoutingDispatcher {
    dispatch(opts, handler) {
        try {
            const hostname = opts.origin
                ? new URL(opts.origin).hostname
                : (opts.host || '').split(':')[0];
            const useProxy = PROXIED_HOSTS.has(hostname);
            return (useProxy ? undiciProxyAgent : directAgent).dispatch(opts, handler);
        } catch {
            return directAgent.dispatch(opts, handler);
        }
    }
    close() { return Promise.all([directAgent.close(), undiciProxyAgent.close()]); }
    destroy() { return Promise.all([directAgent.destroy(), undiciProxyAgent.destroy()]); }
}

setGlobalDispatcher(new RoutingDispatcher());

// ─────── (2) https.request / http.request (для node-telegram-bot-api и др.) ───────
const httpsProxyAgent = new HttpsProxyAgent(PROXY_URL);

// Сохраняем оригинальные методы
const origHttpsRequest = https.request;
const origHttpsGet = https.get;

function wrapRequest(orig) {
    return function patched(...args) {
        // Аргументы могут быть: (url), (url, options), (options), (url, options, callback)
        let url = null;
        let optionsIdx = -1;
        if (typeof args[0] === 'string' || args[0] instanceof URL) {
            try { url = new URL(args[0]); } catch {}
            if (typeof args[1] === 'object' && args[1] !== null && !(args[1] instanceof Function)) {
                optionsIdx = 1;
            }
        } else if (typeof args[0] === 'object' && args[0] !== null) {
            optionsIdx = 0;
            const o = args[0];
            const host = o.hostname || o.host;
            if (host) {
                try { url = new URL(`https://${host}${o.path || '/'}`); } catch {}
            }
        }

        if (url && PROXIED_HOSTS.has(url.hostname)) {
            // Инжектируем agent в options
            if (optionsIdx >= 0) {
                if (!args[optionsIdx].agent) args[optionsIdx].agent = httpsProxyAgent;
            } else {
                // добавляем options как второй аргумент
                args.splice(1, 0, { agent: httpsProxyAgent });
            }
        }
        return orig.apply(this, args);
    };
}

https.request = wrapRequest(origHttpsRequest);
https.get = wrapRequest(origHttpsGet);

// Тихая запись в stderr (попадёт в journalctl)
console.error(`[undici-telegram-proxy] active. proxy=${PROXY_URL} hosts=${[...PROXIED_HOSTS].join(',')} (undici + https.request patched)`);
