import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { existsSync } from 'node:fs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const mobile = resolve(root, 'apps/mobile');
const releaseApp = resolve(mobile, 'build/ios/iphoneos/Runner.app');
const bundleId = 'space.ps6.kiwilens';
const mode = process.argv[2] ?? 'install';

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: options.cwd ?? root,
    encoding: 'utf8',
    stdio: options.stdio ?? 'pipe',
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

function physicalIosDevices() {
  return readJson('flutter', ['devices', '--machine']).filter((device) => {
    const platform = device.targetPlatform?.toLowerCase() ?? '';
    const isIos = platform.includes('ios');
    const isSimulator =
      device.emulator === true ||
      device.isEmulator === true ||
      /simulator/i.test(device.name ?? '');
    return isIos && !isSimulator && device.isSupported !== false;
  });
}

function selectDevice() {
  const devices = physicalIosDevices();
  if (!devices.length) {
    throw new Error(
      'No physical iPhone found. Connect the iPhone to this Mac, unlock it, trust the Mac, enable Developer Mode, then retry.',
    );
  }

  if (devices.length > 1) {
    console.log('Multiple physical iOS devices found; using ' + devices[0].name + '.');
  }
  return devices[0];
}

function ensureIosToolchain() {
  if (process.platform !== 'darwin') {
    throw new Error('iOS builds and device installation require macOS + Xcode.');
  }

  run('xcodebuild', ['-version'], { stdio: 'inherit' });
  run('flutter', ['config', '--enable-swift-package-manager'], {
    stdio: 'inherit',
  });
  run('flutter', ['pub', 'get'], { cwd: mobile, stdio: 'inherit' });
}

function signingHelp(error) {
  console.error('');
  console.error('If Xcode reports a signing/provisioning error, open:');
  console.error('  apps/mobile/ios/Runner.xcworkspace');
  console.error('Then select Runner → Signing & Capabilities → Automatically manage signing');
  console.error('and choose your Apple ID Personal Team once. Afterwards this command can be reused.');
  throw error;
}

function debugOnDevice(device) {
  console.log('Starting Kiwi Lens debug build on ' + device.name + '...');
  const child = spawn(
    'flutter',
    ['run', '-d', device.id, '--no-dds'],
    {
      cwd: mobile,
      stdio: 'inherit',
    },
  );
  child.on('exit', (code) => process.exit(code ?? 0));
}

function buildRelease() {
  console.log('Building signed iOS Release app...');
  try {
    run('flutter', ['build', 'ios', '--release'], {
      cwd: mobile,
      stdio: 'inherit',
    });
  } catch (error) {
    signingHelp(error);
  }

  if (!existsSync(releaseApp)) {
    throw new Error('Release app was not produced at ' + releaseApp);
  }
}

function installRelease(device) {
  buildRelease();

  console.log('Installing Release build on ' + device.name + '...');
  run(
    'xcrun',
    ['devicectl', 'device', 'install', 'app', '--device', device.id, releaseApp],
    { stdio: 'inherit' },
  );

  console.log('Launching Kiwi Lens...');
  try {
    run(
      'xcrun',
      ['devicectl', 'device', 'process', 'launch', '--device', device.id, bundleId],
      { stdio: 'inherit' },
    );
  } catch {
    console.warn('Install succeeded, but automatic launch failed. Open Kiwi Lens from the iPhone home screen.');
  }

  console.log('');
  console.log('Kiwi Lens Release is installed on ' + device.name + '.');
  console.log('Future runs of pnpm mobile:ios:install will rebuild and install the new version over the existing app.');
}

function buildIpa() {
  console.log('Building signed IPA...');
  try {
    run('flutter', ['build', 'ipa', '--release'], {
      cwd: mobile,
      stdio: 'inherit',
    });
  } catch (error) {
    console.error('');
    console.error('IPA export may require an Apple Developer Program distribution profile.');
    signingHelp(error);
  }
  console.log('IPA output: apps/mobile/build/ios/ipa/');
}

function main() {
  ensureIosToolchain();

  if (mode === 'ipa') {
    buildIpa();
    return;
  }

  const device = selectDevice();

  if (mode === 'debug') {
    debugOnDevice(device);
    return;
  }

  if (mode === 'install') {
    installRelease(device);
    return;
  }

  throw new Error('Unknown iOS mode: ' + mode);
}

try {
  main();
} catch (error) {
  console.error('\nKiwi Lens iOS command failed: ' + error.message);
  process.exit(1);
}
