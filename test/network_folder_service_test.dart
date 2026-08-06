import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/services/network_folder_service.dart';

void main() {
  group('NetworkFolderService', () {
    test('recognizes common desktop network path forms', () {
      expect(
        NetworkFolderService.looksLikeNetworkPath(r'\\server\share'),
        isTrue,
      );
      expect(
        NetworkFolderService.looksLikeNetworkPath(r'\\?\UNC\server\share'),
        isTrue,
      );
      expect(
        NetworkFolderService.looksLikeNetworkPath('//server/share'),
        isTrue,
      );
      expect(NetworkFolderService.looksLikeNetworkPath(r'Z:\ROMs'), isTrue);
      expect(
        NetworkFolderService.looksLikeNetworkPath('/Volumes/ROMs'),
        isTrue,
      );
    });

    test('does not classify ordinary local paths as network paths', () {
      expect(
        NetworkFolderService.looksLikeNetworkPath('/home/user/roms'),
        isFalse,
      );
      expect(
        NetworkFolderService.looksLikeNetworkPath('/Users/user/roms'),
        isFalse,
      );
    });
  });
}
