import 'package:path/path.dart' as paths;

/// ZIP entries use forward slashes regardless of the host operating system.
/// Manifest hrefs may contain ../ to refer to a resource next to the OPF
/// directory (for example OEBPS/../jacket.xhtml -> jacket.xhtml).
class ZipPathUtils {
  static String getDirectoryPath(String filePath) {
    var lastSlashIndex = filePath.lastIndexOf('/');
    if (lastSlashIndex == -1) {
      return '';
    } else {
      return filePath.substring(0, lastSlashIndex);
    }
  }

  static String? combine(String? directory, String? fileName) {
    if (fileName == null) return null;
    final combined = directory == null || directory.isEmpty
        ? fileName
        : paths.posix.join(directory, fileName);
    return paths.posix.normalize(combined);
  }
}
