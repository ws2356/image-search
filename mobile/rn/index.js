import { AppRegistry } from 'react-native';
import { run_android_headless_transfer_task } from './features/backup/runtime/android-headless-transfer-task';

AppRegistry.registerHeadlessTask('AuBackupTransferTask', () => run_android_headless_transfer_task);

import 'expo-router/entry';
