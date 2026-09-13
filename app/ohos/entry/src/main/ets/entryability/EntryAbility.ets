import { FlutterAbility, FlutterEngine, MethodChannel, Log } from '@ohos/flutter_ohos';
import { MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import { picker } from '@kit.CoreFileKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';

/**
 * 目录选择通道。
 *
 * 为什么要自己写：file_picker 的 pubspec 里没有 ohos 平台声明，
 * 鸿蒙端没有任何插件被注册（GeneratedPluginRegistrant 是空的），
 * 所以它的 getDirectoryPath() 在鸿蒙上既不会报错也不会打开任何界面。
 *
 * 阶段 1（当前）：用系统文件选择器让用户选 .md 文件，复制进应用沙箱的一个子目录，
 * 再把该目录路径交给 Dart —— 这样完全走 dart:io，不需要持久化 uri 授权。
 * 阶段 2（未做）：让用户选目录并持久化 uri 授权，直接原地读写。
 */
const TAG = 'YanDirPicker';
const CHANNEL = 'dev.yan/dir_picker';
const IMPORT_SUBDIR = 'yan-library';

export default class EntryAbility extends FlutterAbility {
  private channel: MethodChannel | null = null;
  private importDir: string = '';

  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)

    const ctx = this.context as common.UIAbilityContext;
    this.importDir = ctx.filesDir + '/' + IMPORT_SUBDIR;

    this.channel = new MethodChannel(flutterEngine.dartExecutor, CHANNEL);
    this.channel.setMethodCallHandler({
      onMethodCall: (call, result) => {
        Log.i(TAG, 'onMethodCall: ' + call.method)
        if (call.method === 'pickDirectory') {
          this.pickAndImport(result)
        } else if (call.method === 'exportFile') {
          this.exportFile(call.argument('name') as string, result)
        } else if (call.method === 'ensureLibraryDir') {
          // 启动时就把沙箱库目录建好。
          // 否则用户在"还没导入过任何笔记"的状态下点新建会失败 —— 库根不存在，
          // 而 createNote 是往库根写的。
          try {
            if (!fs.accessSync(this.importDir)) {
              fs.mkdirSync(this.importDir);
            }
            result.success(this.importDir);
          } catch (err) {
            Log.e(TAG, 'ensureLibraryDir failed: ' + JSON.stringify(err))
            result.error('MKDIR_FAILED', '创建库目录失败：' + (err?.message ?? ''), null)
          }
        } else {
          result.notImplemented()
        }
      }
    })
    Log.i(TAG, 'channel registered: ' + CHANNEL + ', importDir=' + this.importDir)
  }

  /**
   * 导出：让用户选保存位置，把内容写过去。
   *
   * 为什么要这个：鸿蒙的 DocumentViewPicker 只能选文件、不能选目录，
   * 所以"选一个文件夹原地读写"做不到。当前模型是导入到沙箱再编辑，
   * 那就必须给一条把改动送回去的路，否则用户的编辑永远出不了沙箱。
   */
  private exportFile(name: string, result: MethodResult): void {
    if (!name) {
      result.error('BAD_ARGS', '缺少文件名', null)
      return
    }
    const ctx = this.context as common.UIAbilityContext;
    try {
      const savePicker = new picker.DocumentViewPicker(ctx);
      const options = new picker.DocumentSaveOptions();
      options.newFileNames = [name];
      options.fileSuffixChoices = ['.md', '.markdown', '.txt'];

      savePicker.save(options)
        .then((uris: Array<string>) => {
          if (!uris || uris.length === 0) {
            result.success(null)   // 用户取消
            return
          }
          const dest = uris[0];
          const src = fs.openSync(`${this.importDir}/${name}`, fs.OpenMode.READ_ONLY);
          try {
            const out = fs.openSync(dest, fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
            try {
              fs.copyFileSync(src.fd, out.fd);
            } finally {
              fs.closeSync(out);
            }
          } finally {
            fs.closeSync(src);
          }
          Log.i(TAG, 'exported ' + name + ' -> ' + dest);
          result.success(dest);
        })
        .catch((err: Error) => {
          Log.e(TAG, 'save failed: ' + JSON.stringify(err))
          result.error('EXPORT_FAILED', '导出失败：' + (err?.message ?? ''), null)
        })
    } catch (err) {
      Log.e(TAG, 'export threw: ' + JSON.stringify(err))
      result.error('EXPORT_FAILED', '导出失败：' + (err?.message ?? ''), null)
    }
  }

  /** 打开系统文件选择器，把选中的笔记复制进沙箱，返回沙箱目录路径。 */
  private pickAndImport(result: MethodResult): void {
    const ctx = this.context as common.UIAbilityContext;
    const documentPicker = new picker.DocumentViewPicker(ctx);

    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 200;
    options.fileSuffixFilters = ['.md', '.markdown', '.mdown', '.mkd', '.txt'];

    documentPicker.select(options)
      .then((uris: Array<string>) => {
        if (!uris || uris.length === 0) {
          result.success(null)   // 用户取消
          return
        }
        this.copyAll(uris, result)
      })
      .catch((err: Error) => {
        Log.e(TAG, 'select failed: ' + JSON.stringify(err))
        result.error('PICK_FAILED', '选择失败：' + (err?.message ?? ''), null)
      })
  }

  private copyAll(uris: Array<string>, result: MethodResult): void {
    try {
      if (!fs.accessSync(this.importDir)) {
        fs.mkdirSync(this.importDir)
      }
      let copied = 0
      for (const uri of uris) {
        const name = this.fileNameFromUri(uri)
        if (name.length === 0) continue
        const src = fs.openSync(uri, fs.OpenMode.READ_ONLY)
        try {
          fs.copyFileSync(src.fd, this.importDir + '/' + name)
          copied++
        } finally {
          fs.closeSync(src)
        }
      }
      Log.i(TAG, 'imported ' + copied + ' of ' + uris.length)
      if (copied === 0) {
        result.error('IMPORT_FAILED', '没有成功导入任何笔记', null)
        return
      }
      result.success(this.importDir)
    } catch (err) {
      Log.e(TAG, 'copy failed: ' + JSON.stringify(err))
      result.error('IMPORT_FAILED', '导入失败：' + (err?.message ?? ''), null)
    }
  }

  private fileNameFromUri(uri: string): string {
    const parts = uri.split('/')
    const raw = parts[parts.length - 1]
    if (!raw || raw.length === 0) return ''
    try {
      return decodeURIComponent(raw)
    } catch (e) {
      return raw
    }
  }
}
