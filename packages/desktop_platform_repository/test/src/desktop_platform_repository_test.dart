import 'dart:typed_data';

import 'package:desktop_platform_api/desktop_platform_api.dart';
import 'package:desktop_platform_repository/desktop_platform_repository.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

final class _DirectoryPicker extends Mock implements DirectoryPickerApi {}

final class _FilePicker extends Mock implements FilePickerApi {}

final class _Clipboard extends Mock implements ClipboardApi {}

final class _Window extends Mock implements WindowCommandApi {}

final class _Menu extends Mock implements MenuCommandApi {}

final class _FileManager extends Mock implements SystemFileManagerApi {}

void main() {
  late _DirectoryPicker directoryPicker;
  late _FilePicker filePicker;
  late _Clipboard clipboard;
  late _Window window;
  late _Menu menu;
  late _FileManager fileManager;
  late DesktopPlatformRepository repository;

  setUpAll(() {
    registerFallbackValue(
      const MenuConfiguration(fileMenuLabel: 'File', openProjectLabel: 'Open'),
    );
  });

  setUp(() {
    directoryPicker = _DirectoryPicker();
    filePicker = _FilePicker();
    clipboard = _Clipboard();
    window = _Window();
    menu = _Menu();
    fileManager = _FileManager();
    repository = DesktopPlatformRepository(
      directoryPicker: directoryPicker,
      filePicker: filePicker,
      clipboard: clipboard,
      window: window,
      menu: menu,
      fileManager: fileManager,
    );
  });

  group('DesktopPlatformRepository', () {
    test('forwards directory and file picker requests', () async {
      when(
        () => directoryPicker.pickDirectory(initialDirectory: 'C:/work'),
      ).thenAnswer((_) async => 'C:/work/zeta');
      when(
        () => filePicker.pickFiles(acceptedTypes: any(named: 'acceptedTypes')),
      ).thenAnswer((_) async => ['C:/image.png']);
      final filter = FileTypeFilter(
        label: 'Images',
        extensions: const ['png'],
      );

      expect(
        await repository.pickDirectory(initialDirectory: 'C:/work'),
        'C:/work/zeta',
      );
      expect(
        await repository.pickFiles(acceptedTypes: [filter]),
        ['C:/image.png'],
      );
      verify(
        () => filePicker.pickFiles(acceptedTypes: [filter]),
      ).called(1);
    });

    test('forwards every clipboard projection', () async {
      final bytes = Uint8List.fromList([1, 2]);
      when(() => clipboard.writeText('copy')).thenAnswer((_) async {});
      when(clipboard.readText).thenAnswer((_) async => 'paste');
      when(clipboard.readImage).thenAnswer((_) async => bytes);
      when(clipboard.readFilePaths).thenAnswer((_) async => ['C:/a.txt']);

      await repository.copyText('copy');

      expect(await repository.readText(), 'paste');
      expect(await repository.readImage(), bytes);
      expect(await repository.readFilePaths(), ['C:/a.txt']);
      verify(() => clipboard.writeText('copy')).called(1);
    });

    test('opens directories through the system file manager', () async {
      when(() => fileManager.openDirectory('C:/work')).thenAnswer((_) async {});
      await repository.openDirectory('C:/work');
      verify(() => fileManager.openDirectory('C:/work')).called(1);
    });

    test('requires configured optional picker and file manager', () {
      final minimal = DesktopPlatformRepository(
        directoryPicker: directoryPicker,
        clipboard: clipboard,
        window: window,
        menu: menu,
      );
      expect(minimal.pickFiles, throwsStateError);
      expect(() => minimal.openDirectory('C:/work'), throwsStateError);
    });

    test(
      'translates platform failures without exposing details in text',
      () async {
        when(
          () => directoryPicker.pickDirectory(),
        ).thenThrow(StateError('private path'));

        final failure = await _failureOf(repository.pickDirectory());

        expect(failure.operation, DesktopPlatformOperation.pickDirectory);
        expect(failure.cause, isA<StateError>());
        expect(
          failure.toString(),
          'DesktopPlatformException(DesktopPlatformOperation.pickDirectory)',
        );
      },
    );
  });

  group('DesktopWindowCommands', () {
    test('forwards lifecycle and commands', () async {
      when(() => window.lifecycle).thenAnswer(
        (_) => Stream.value(WindowLifecycleEvent.focused),
      );
      when(window.minimize).thenAnswer((_) async {});
      when(window.toggleMaximize).thenAnswer((_) async {});
      when(window.close).thenAnswer((_) async {});

      expect(
        await repository.windowCommands.lifecycle.first,
        WindowLifecycleEvent.focused,
      );
      await repository.windowCommands.minimize();
      await repository.windowCommands.toggleMaximize();
      await repository.windowCommands.close();

      verify(window.minimize).called(1);
      verify(window.toggleMaximize).called(1);
      verify(window.close).called(1);
    });
  });

  group('DesktopMenuCommands', () {
    test('forwards command stream and configuration', () async {
      when(() => menu.commands).thenAnswer(
        (_) => Stream.value(MenuCommand.openProject),
      );
      when(() => menu.configure(any())).thenAnswer((_) async => true);
      when(
        () => menu.setMenuEnabled(
          commandId: any(named: 'commandId'),
          enabled: any(named: 'enabled'),
        ),
      ).thenAnswer((_) async {});
      const configuration = MenuConfiguration(
        fileMenuLabel: 'File',
        openProjectLabel: 'Open',
      );

      expect(
        await repository.menuCommands.commands.first,
        MenuCommand.openProject,
      );
      expect(await repository.menuCommands.configure(configuration), isTrue);
      await repository.menuCommands.setEnabled(
        commandId: 'openProject',
        enabled: false,
      );

      verify(() => menu.configure(configuration)).called(1);
      verify(
        () => menu.setMenuEnabled(
          commandId: 'openProject',
          enabled: false,
        ),
      ).called(1);
    });
  });
}

Future<DesktopPlatformException> _failureOf(Future<Object?> future) async {
  try {
    await future;
  } on DesktopPlatformException catch (error) {
    return error;
  }
  throw StateError('Expected DesktopPlatformException');
}
