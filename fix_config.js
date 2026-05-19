const fs = require('fs');

const path = 'config/openclaw.json';
const data = fs.readFileSync(path, 'utf8');
let obj = JSON.parse(data);

// Remove root keys
delete obj["modelAliases"];
delete obj["premiumGuard"];
delete obj["spending"];
delete obj["voice"];
delete obj["image"];
delete obj["fs"];
delete obj["sandbox"];
delete obj["selfImprovement"];
delete obj["// =================================================================="];
delete obj["// OpenClaw configuration — итоговый конфиг для VPS"];
delete obj["// Скопируется на VPS как ~/.openclaw/openclaw.json через scripts/deploy.sh"];
delete obj["// Плейсхолдеры ${VAR} автоматически заменяются из .env"];

// Remove nested keys
if (obj.tools && obj.tools.exec) {
    delete obj.tools.exec.allowlist;
    delete obj.tools.exec.blocklist;
}
if (obj.tools) {
    delete obj.tools.browser;
    delete obj.tools["// КРИТИЧНО: profile=full включает browser. profile=messaging его отключает!"];
}
if (obj.gateway) {
    delete obj.gateway.configReload;
}
if (obj.memory) {
    delete obj.memory.search;
    delete obj.memory.dailyLogs;
    delete obj.memory.privacy;
}
if (obj.mcp) {
    delete obj.mcp["// Подтверждённые npm-пакеты по АУДИТу. НЕ @microsoft/mcp-server-playwright (его нет!)"];
}

fs.writeFileSync(path, JSON.stringify(obj, null, 2), 'utf8');
console.log('Fixed config saved!');
