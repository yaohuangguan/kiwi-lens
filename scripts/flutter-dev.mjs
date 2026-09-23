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

function readJson(command, args) {
  return JSON.parse(run(command, args) || '[]');
}

function sleep(ms) {
  return new Promise((resolveSleep) => setTimeout(resolveSleep, ms));
}

function pickAndroidDevice(devices) {
  return devices.find((device) =>
    device.targetPlatform?.toLowerCase().includes('android') && device.isSupported !== false,
  );
}

async function waitForAndroidDevice() {
  for (let attempt = 0; attempt < 30; attempt += 1) {
    const device = pickAndroidDevice(readJson('flutter', ['devices', '--machine']));
    if (device) return device;
    await sleep(2000);
  }
  return null;
}

async function main() {
  run('flutter', ['--version'], { stdio: 'inherit' });
  run('flutter', ['pub', 'get'], { cwd: mobile, stdio: 'inherit' });

  let device = pickAndroidDevice(readJson('flutter', ['devices', '--machine']));

  if (!device) {
    const emulators = readJson('flutter', ['emulators', '--machine']);
    const emulator = emulators.find((item) =>
      item.id?.toLowerCase().includes('android') ||
      item.name?.toLowerCase().includes('android') ||
      item.category?.toLowerCase().includes('mobile'),
    ) ?? emulators[0];

    if (!emulator) {
      throw new Error(
        'No Android emulator found. Create one in Android Studio Device Manager, then run pnpm mobile:dev again.',
      );
    }

    console.log('Launching emulator: ' + (emulator.name ?? emulator.id));
    run('flutter', ['emulators', '--launch', emulator.id], { stdio: 'inherit' });
    device = await waitForAndroidDevice();
  }

  if (!device) {
    throw new Error('Android emulator did not become available to Flutter.');
  }

  console.log('Running Kiwi Lens on ' + device.name + ' (' + device.id + ')');
  const child = spawn('flutter', ['run', '-d', device.id], {
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
