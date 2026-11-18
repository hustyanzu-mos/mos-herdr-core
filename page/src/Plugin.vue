<template>
  <div>
    <h2 class="mb-4">HerdrCore</h2>

    <v-skeleton-loader v-if="loading" :loading="true" type="card" />

    <div v-else style="margin-bottom: 80px">
      <v-alert
        v-if="error"
        type="error"
        variant="tonal"
        closable
        class="mb-4"
        @click:close="error = ''"
      >
        {{ error }}
      </v-alert>

      <!-- Status -->
      <v-card class="mb-4 pa-0">
        <v-card-title class="d-flex align-center">
          <v-icon class="mr-2">mdi-console</v-icon>
          <span>Status</span>
          <v-spacer />
          <v-chip :color="running ? 'success' : 'grey'" size="small" variant="tonal">
            {{ running ? 'Running' : 'Stopped' }}
          </v-chip>
        </v-card-title>
        <v-card-text>
          <v-row>
            <v-col cols="12" md="3">
              <div class="text-caption text-medium-emphasis">Installed</div>
              <div class="text-subtitle-1 font-weight-medium">{{ settings.version || 'Not installed' }}</div>
            </v-col>
            <v-col cols="12" md="3">
              <div class="text-caption text-medium-emphasis">Latest</div>
              <div class="text-subtitle-1 font-weight-medium">{{ latestVersion || '-' }}</div>
            </v-col>
            <v-col cols="6" md="2">
              <div class="text-caption text-medium-emphasis">PID</div>
              <div class="text-subtitle-1 font-weight-medium">{{ running ? (status.pid || '-') : '-' }}</div>
            </v-col>
            <v-col cols="6" md="2">
              <div class="text-caption text-medium-emphasis">Terminals</div>
              <div class="text-subtitle-1 font-weight-medium">{{ running ? status.live : '-' }}</div>
            </v-col>
            <v-col cols="12" md="2">
              <div class="text-caption text-medium-emphasis">Uptime</div>
              <div class="text-subtitle-1 font-weight-medium">{{ uptimeText }}</div>
            </v-col>
          </v-row>

          <div class="d-flex flex-wrap ga-2 mt-4">
            <v-btn size="small" variant="tonal" color="secondary" :loading="checking" @click="checkForUpdates">
              Check updates
            </v-btn>
            <v-btn
              v-if="!settings.version"
              size="small"
              color="primary"
              :loading="installing"
              @click="installCore"
            >
              Install
            </v-btn>
            <v-btn
              v-else-if="updateAvailable"
              size="small"
              color="primary"
              :loading="updating"
              @click="updateCore"
            >
              Update to {{ latestVersion }}
            </v-btn>
            <v-btn size="small" color="primary" :disabled="running || !settings.version" :loading="starting" @click="startCore">
              Start
            </v-btn>
            <v-btn size="small" color="error" variant="outlined" :disabled="!running" :loading="stopping" @click="stopCore">
              Stop
            </v-btn>
            <v-btn size="small" variant="tonal" :disabled="!settings.version" :loading="restarting" @click="restartCore">
              Restart
            </v-btn>
            <v-btn size="small" variant="text" @click="refreshAll">Refresh</v-btn>
          </div>
        </v-card-text>
      </v-card>

      <!-- Connect -->
      <v-card class="mb-4 pa-0">
        <v-card-title class="d-flex align-center">
          <v-icon class="mr-2">mdi-ssh</v-icon>
          <span>Connect</span>
        </v-card-title>
        <v-card-text>
          <p class="text-body-2 mb-3">
            Herdr Core only exposes a Unix socket. Remote access goes over SSH, so enable
            <strong>Settings &rarr; Network Services &rarr; SSH</strong> in MOS first.
          </p>
          <v-text-field
            :model-value="sshCommand"
            label="Run from your workstation"
            readonly
            density="compact"
            variant="outlined"
            hide-details
          >
            <template #append-inner>
              <v-btn icon="mdi-content-copy" size="small" variant="text" @click="copy(sshCommand)" />
            </template>
          </v-text-field>
          <v-text-field
            :model-value="machineCommand"
            label="Or add this NAS as a Herdr machine"
            readonly
            density="compact"
            variant="outlined"
            hide-details
            class="mt-3"
          >
            <template #append-inner>
              <v-btn icon="mdi-content-copy" size="small" variant="text" @click="copy(machineCommand)" />
            </template>
          </v-text-field>
          <p class="text-caption text-medium-emphasis mt-2">
            The <code>hc</code> wrapper always points at the persistent core. No TCP port is opened.
            If <code>hc machine add</code> offers to copy hc to this NAS, answer <strong>No</strong>:
            the plugin already provides <code>/usr/bin/hc</code>. Do not use <code>hc machine update</code> here.
          </p>
        </v-card-text>
      </v-card>

      <!-- Settings -->
      <v-card class="mb-4 pa-0">
        <v-card-title class="d-flex align-center">
          <v-icon class="mr-2">mdi-cog</v-icon>
          <span>Settings</span>
        </v-card-title>
        <v-card-text>
          <v-switch
            v-model="form.auto_start"
            label="Start automatically after MOS services"
            color="primary"
            inset
            hide-details
          />
          <v-switch
            v-model="form.auto_install"
            label="Download the binary automatically when missing"
            color="primary"
            inset
            hide-details
            class="mt-2"
          />
          <v-text-field
            v-model="form.work_dir"
            label="Default working directory"
            hint="Where new terminals start. Empty or missing paths fall back to /."
            persistent-hint
            class="mt-4"
          />
          <v-text-field
            v-model="form.pin_version"
            label="Pin Herdr Core version (optional)"
            hint="Example: 0.1.21. Empty means the latest release."
            persistent-hint
            class="mt-4"
          />
          <v-btn color="primary" class="mt-4" :loading="saving" @click="saveSettings">
            <v-icon start>mdi-content-save</v-icon>
            Save
          </v-btn>
        </v-card-text>
      </v-card>

      <!-- Logs -->
      <v-card class="pa-0">
        <v-card-title class="d-flex align-center">
          <v-icon class="mr-2">mdi-text-box-outline</v-icon>
          <span>Logs</span>
          <v-spacer />
          <v-btn size="small" variant="text" :loading="loadingLogs" @click="loadLogs">Refresh</v-btn>
        </v-card-title>
        <v-card-text>
          <pre class="herdr-log">{{ logs || 'No log output yet.' }}</pre>
        </v-card-text>
      </v-card>
    </div>

    <v-snackbar v-model="snackbar" :color="snackbarColor" timeout="4000">
      {{ snackbarText }}
    </v-snackbar>
  </div>
</template>

<script setup>
import { ref, reactive, computed, onMounted, onUnmounted } from 'vue';

const PLUGIN_NAME = 'herdr-core';

const DEFAULT_SETTINGS = {
  auto_start: true,
  auto_install: true,
  pin_version: '',
  version: '',
  work_dir: '',
};

const loading = ref(true);
const saving = ref(false);
const checking = ref(false);
const installing = ref(false);
const updating = ref(false);
const starting = ref(false);
const stopping = ref(false);
const restarting = ref(false);
const loadingLogs = ref(false);

const running = ref(false);
const status = reactive({ pid: 0, live: 0, uptime_ms: 0 });
const latestVersion = ref('');
const updateAvailable = ref(false);
const logs = ref('');
const error = ref('');

const snackbar = ref(false);
const snackbarText = ref('');
const snackbarColor = ref('success');

const settings = reactive({ ...DEFAULT_SETTINGS });
const form = reactive({
  auto_start: true,
  auto_install: true,
  work_dir: '',
  pin_version: '',
});

let timer = null;

const authHeaders = () => ({
  Authorization: 'Bearer ' + (localStorage.getItem('authToken') || ''),
});

const jsonHeaders = () => ({
  ...authHeaders(),
  'Content-Type': 'application/json',
});

const sshCommand = computed(() => `ssh root@${window.location.hostname} hc ls`);
const machineCommand = computed(() => `hc machine add ${window.location.hostname}`);

const uptimeText = computed(() => {
  if (!running.value || !status.uptime_ms) return '-';
  const seconds = Math.floor(status.uptime_ms / 1000);
  if (seconds < 60) return `${seconds}s`;
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m`;
  const hours = Math.floor(minutes / 60);
  return `${hours}h ${minutes % 60}m`;
});

function notify(text, color = 'success') {
  snackbarText.value = text;
  snackbarColor.value = color;
  snackbar.value = true;
}

function setError(e) {
  error.value = e instanceof Error ? e.message : String(e);
  notify(error.value, 'error');
}

function parseOutput(data) {
  let output = data?.output;
  if (typeof output === 'string') {
    try {
      output = JSON.parse(output);
    } catch {
      // keep the string
    }
  }
  return output;
}

async function query(args, parseJson = false, timeout = 60) {
  const res = await fetch('/api/v1/mos/plugins/query', {
    method: 'POST',
    headers: jsonHeaders(),
    body: JSON.stringify({
      command: PLUGIN_NAME,
      args,
      timeout,
      parse_json: parseJson,
    }),
  });
  if (!res.ok) throw new Error(`Plugin query failed: HTTP ${res.status}`);
  const data = await res.json();
  if (data && data.success === false) {
    throw new Error(data.error || data.message || 'Plugin query failed');
  }
  return data;
}

async function fetchSettings() {
  const res = await fetch(`/api/v1/mos/plugins/settings/${PLUGIN_NAME}`, {
    headers: authHeaders(),
  });
  if (!res.ok) throw new Error(`Settings request failed: HTTP ${res.status}`);
  const raw = await res.json();
  const data = raw && raw.data && typeof raw.data === 'object' ? raw.data : raw;

  for (const key of Object.keys(DEFAULT_SETTINGS)) {
    if (data[key] !== undefined && data[key] !== null) {
      settings[key] = data[key];
    }
  }

  form.auto_start = settings.auto_start === true;
  form.auto_install = settings.auto_install === true;
  form.work_dir = settings.work_dir || '';
  form.pin_version = settings.pin_version || '';
}

async function saveSettings() {
  saving.value = true;
  try {
    const payload = {
      auto_start: form.auto_start,
      auto_install: form.auto_install,
      work_dir: form.work_dir.trim(),
      pin_version: form.pin_version.trim(),
      version: settings.version || '',
    };
    const res = await fetch(`/api/v1/mos/plugins/settings/${PLUGIN_NAME}`, {
      method: 'POST',
      headers: jsonHeaders(),
      body: JSON.stringify(payload),
    });
    if (!res.ok) throw new Error(`Save failed: HTTP ${res.status}`);
    Object.assign(settings, payload);
    notify('Settings saved');
  } catch (e) {
    setError(e);
  } finally {
    saving.value = false;
  }
}

async function refreshStatus() {
  try {
    const data = await query(['status'], true, 10);
    const out = parseOutput(data) || {};
    running.value = out.running === true;
    status.pid = Number(out.pid) || 0;
    status.live = Number(out.live) || 0;
    status.uptime_ms = Number(out.uptime_ms) || 0;
    if (out.version && out.version !== 'not installed') {
      settings.version = out.version;
    }
  } catch {
    running.value = false;
    status.pid = 0;
    status.live = 0;
    status.uptime_ms = 0;
  }
}

async function checkForUpdates() {
  checking.value = true;
  try {
    const data = await query(['check_version'], true, 40);
    const out = parseOutput(data) || {};
    latestVersion.value = out.latest || '';
    updateAvailable.value = Boolean(settings.version) && out.update_available === true;
  } catch (e) {
    setError(e);
  } finally {
    checking.value = false;
  }
}

async function refreshAll() {
  loading.value = true;
  try {
    await fetchSettings();
    await refreshStatus();
    await checkForUpdates();
  } catch (e) {
    setError(e);
  } finally {
    loading.value = false;
  }
}

async function installCore() {
  installing.value = true;
  try {
    await query(['install_binary'], false, 180);
    await fetchSettings();
    await refreshStatus();
    await checkForUpdates();
    notify('Herdr Core installed');
  } catch (e) {
    setError(e);
  } finally {
    installing.value = false;
  }
}

async function updateCore() {
  updating.value = true;
  try {
    await query(['install_binary'], false, 180);
    await fetchSettings();
    await refreshStatus();
    await checkForUpdates();
    notify('Herdr Core updated');
  } catch (e) {
    setError(e);
  } finally {
    updating.value = false;
  }
}

async function startCore() {
  starting.value = true;
  try {
    await query(['start'], false, 60);
    await refreshStatus();
    notify('Herdr Core started');
  } catch (e) {
    setError(e);
  } finally {
    starting.value = false;
  }
}

async function stopCore() {
  stopping.value = true;
  try {
    await query(['stop'], false, 60);
    await refreshStatus();
    notify('Herdr Core stopped');
  } catch (e) {
    setError(e);
  } finally {
    stopping.value = false;
  }
}

async function restartCore() {
  restarting.value = true;
  try {
    await query(['restart'], false, 90);
    await refreshStatus();
    notify('Herdr Core restarted');
  } catch (e) {
    setError(e);
  } finally {
    restarting.value = false;
  }
}

async function loadLogs() {
  loadingLogs.value = true;
  try {
    const data = await query(['logs'], false, 20);
    const out = data?.output;
    logs.value = typeof out === 'string' ? out : JSON.stringify(out ?? data, null, 2);
  } catch (e) {
    setError(e);
  } finally {
    loadingLogs.value = false;
  }
}

async function copy(text) {
  try {
    if (navigator.clipboard && window.isSecureContext) {
      await navigator.clipboard.writeText(text);
    } else {
      const area = document.createElement('textarea');
      area.value = text;
      document.body.appendChild(area);
      area.select();
      document.execCommand('copy');
      document.body.removeChild(area);
    }
    notify('Copied');
  } catch {
    notify('Copy failed', 'error');
  }
}

onMounted(async () => {
  loading.value = true;
  try {
    await fetchSettings();
    await refreshStatus();
    await checkForUpdates();
  } catch (e) {
    setError(e);
  } finally {
    loading.value = false;
  }
  timer = setInterval(refreshStatus, 8000);
});

onUnmounted(() => {
  if (timer) clearInterval(timer);
});
</script>

<style scoped>
.herdr-log {
  max-height: 360px;
  overflow: auto;
  background: rgba(0, 0, 0, 0.25);
  padding: 12px;
  border-radius: 8px;
  font-size: 12px;
  line-height: 1.4;
  white-space: pre-wrap;
  word-break: break-word;
}
</style>