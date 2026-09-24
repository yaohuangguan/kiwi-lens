import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const mobile = resolve(root, 'apps/mobile');

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: options.cwd ?? root,
    encoding: 'utf8',
    stdio: options.stdio ?? 'pipe',
    shell: process.platform === 'win32',
  });
  if (result.status !== 0) {
    if (result.stdout) process.stdout.write(result.stdout);
    if (result.stderr) process.stderr.write(result.stderr);
    throw new Error(command + ' ' + args.join(' ') + ' failed');
  }
  return result.stdout ?? '';
}

function tryRun(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: options.cwd ?? root,
    encoding: 'utf8',
    stdio: options.stdio ?? 'pipe',
    shell: process.platform === 'win32',
  });
  return {
    ok: result.status === 0,
    stdout: result.stdout ?? '',
    stderr: result.stderr ?? '',
  };
}

function readJson(command, args) {
  return JSON.parse(run(command, args) || '[]');
}

function sleep(ms) {
  return new Promise((resolveSleep) => setTimeout(resolveSleep, ms));
}

function isSupportedMobileDevice(device) {
  const platform = device.targetPlatform?.toLowerCase() ?? '';
  return device.isSupported !== false &&
    (platform.includes('android') || platform.includes('ios'));
}

function pickMobileDevice(devices) {
  const supported = devices.filter(isSupportedMobileDevice);
  if (process.platform === 'darwin') {
    return supported.find((device) =>
      device.targetPlatform?.toLowerCase().includes('ios'),
    ) ?? supported.find((device) =>
      device.targetPlatform?.toLowerCase().includes('android'),
    );
  }
  return supported.find((device) =>
    device.targetPlatform?.toLowerCase().includes('android'),
  ) ?? supported.find((device) =>
    device.targetPlatform?.toLowerCase().includes('ios'),
  );
}

async function waitForMobileDevice(preferredPlatform) {
  for (let attempt = 0; attempt < 45; attempt += 1) {
    const devices = readJson('flutter', ['devices', '--machine']);
    const matching = preferredPlatform
      ? devices.find((device) =>
          isSupportedMobileDevice(device) &&
          device.targetPlatform?.toLowerCase().includes(preferredPlatform),
        )
      : pickMobileDevice(devices);
    if (matching) return matching;
    await sleep(2000);
  }
  return null;
}

function ensureSwiftPackageManager() {
  if (process.platform !== 'darwin') return;

  console.log('Ensuring Flutter Swift Package Manager support is enabled...');
  run('flutter', ['config', '--enable-swift-package-manager'], {
    stdio: 'inherit',
  });
}

function parseFlutterEmulators(output) {
  return output
    .split(/\r?\n/)
    .map((line) => line.split('•').map((part) => part.trim()))
    .filter((parts) =>
      parts.length >= 4 &&
      parts[0] &&
      parts[0].toLowerCase() !== 'id' &&
      !parts[0].startsWith('-'),
    )
    .map(([id, name, manufacturer, platform]) => ({
      id,
      name,
      manufacturer,
      platform,
    }));
}

async function launchAndroidEmulator() {
  const output = run('flutter', ['emulators']);
  const emulators = parseFlutterEmulators(output);
  const emulator = emulators.find((item) =>
    item.platform?.toLowerCase().includes('android') ||
    item.id?.toLowerCase().includes('android') ||
    item.name?.toLowerCase().includes('android'),
  );

  if (!emulator) return null;

  console.log('Launching Android emulator: ' + (emulator.name || emulator.id));
  run('flutter', ['emulators', '--launch', emulator.id], { stdio: 'inherit' });
  return waitForMobileDevice('android');
}

function iosRuntimeVersion(runtimeId) {
  const match = runtimeId.match(/iOS-(\d+)(?:-(\d+))?/i);
  if (!match) return [0, 0];
  return [Number(match[1]), Number(match[2] ?? 0)];
}

async function launchIosSimulator() {
  if (process.platform !== 'darwin') return null;

  const result = tryRun('xcrun', ['simctl', 'list', 'devices', 'available', '--json']);
  if (!result.ok) return null;

  let payload;
  try {
    payload = JSON.parse(result.stdout);
  } catch {
    return null;
  }

  const runtimes = Object.entries(payload.devices ?? {})
    .filter(([runtime]) => runtime.includes('iOS-'))
    .sort(([a], [b]) => {
      const [aMajor, aMinor] = iosRuntimeVersion(a);
      const [bMajor, bMinor] = iosRuntimeVersion(b);
      return bMajor - aMajor || bMinor - aMinor;
    });

  const candidates = runtimes.flatMap(([, devices]) =>
    (devices ?? []).filter((device) =>
      device.isAvailable !== false && /^iPhone/i.test(device.name ?? ''),
    ),
  );

  const device = candidates.find((item) => item.state === 'Booted') ??
    candidates.find((item) => /Pro Max/i.test(item.name ?? '')) ??
    candidates[0];

  if (!device) return null;

  if (device.state !== 'Booted') {
    console.log('Booting iOS Simulator: ' + device.name);
    const boot = tryRun('xcrun', ['simctl', 'boot', device.udid]);
    if (!boot.ok && !/current state: Booted/i.test(boot.stderr)) {
      if (boot.stderr) process.stderr.write(boot.stderr);
      return null;
    }
  }

  tryRun('open', ['-a', 'Simulator']);
  return waitForMobileDevice('ios');
}

async function main() {
  run('flutter', ['--version'], { stdio: 'inherit' });
  ensureSwiftPackageManager();
  run('flutter', ['pub', 'get'], { cwd: mobile, stdio: 'inherit' });

  let device = pickMobileDevice(readJson('flutter', ['devices', '--machine']));

  if (!device && process.platform === 'darwin') {
    device = await launchIosSimulator();
  }

  if (!device) {
    device = await launchAndroidEmulator();
  }

  if (!device) {
    throw new Error(
      process.platform === 'darwin'
        ? 'No supported mobile device found. Open Xcode Simulator or connect an iPhone, then run pnpm mobile:dev again.'
        : 'No Android device/emulator found. Create an AVD in Android Studio Device Manager, then run pnpm mobile:dev again.',
    );
  }

  console.log('Running Kiwi Lens on ' + device.name + ' (' + device.id + ')');

  const targetPlatform = device.targetPlatform?.toLowerCase() ?? '';
  const runArgs = ['run', '-d', device.id];

  // Flutter 3.47 can intermittently fail to connect its local Dart Development
  // Service proxy after an otherwise successful iOS build. Going directly to
  // the VM service avoids the localhost DDS WebSocket failure while preserving
  // the normal flutter run development loop and hot reload.
  if (process.platform === 'darwin' && targetPlatform.includes('ios')) {
    runArgs.push('--no-dds');
    console.log('iOS development: DDS disabled to use the VM service directly.');
  }

  const child = spawn('flutter', runArgs, {
    cwd: mobile,
    stdio: 'inherit',
    shell: process.platform === 'win32',
  });

  child.on('exit', (code) => process.exit(code ?? 0));
}

main().catch((error) => {
  console.error('\nKiwi Lens Flutter dev failed: ' + error.message);
  process.exit(1);
});
