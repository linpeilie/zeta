import 'dart:async';
import 'dart:io';

/// 使用同目录临时文件替换目标文件的 UTF-8 文本存储。
///
/// 同一实例的写入会串行执行，避免应用内并发保存互相覆盖。临时文件与目标文件
/// 位于同一目录，完成 flush 后再 rename，降低进程中断留下半份 JSON 的概率。
class AtomicTextFile {
  AtomicTextFile(this.file);

  /// 最终持久化文件。
  final File file;

  Future<void> _writeTail = Future<void>.value();

  /// 文件不存在时返回 null；其他文件系统异常交给调用方按 feature 语义处理。
  Future<String?> read() async {
    if (!await file.exists()) {
      return null;
    }
    return file.readAsString();
  }

  /// 串行、原子地替换文件内容。
  Future<void> write(String value) {
    final operation = _writeTail.then((_) => _writeAtomically(value));
    _writeTail = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _writeAtomically(String value) async {
    await file.parent.create(recursive: true);
    final temporaryFile = File(
      '${file.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      await temporaryFile.writeAsString(value, flush: true);
      await temporaryFile.rename(file.path);
    } finally {
      if (await temporaryFile.exists()) {
        await temporaryFile.delete();
      }
    }
  }
}
