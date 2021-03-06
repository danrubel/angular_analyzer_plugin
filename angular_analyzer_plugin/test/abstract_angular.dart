import 'package:analyzer/context/context_root.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/error/listener.dart';
import 'package:analyzer/file_system/file_system.dart';
import 'package:analyzer/file_system/memory_file_system.dart';
import 'package:analyzer/source/package_map_resolver.dart';
import 'package:analyzer/src/dart/analysis/byte_store.dart';
import 'package:analyzer/src/dart/analysis/driver.dart'
    show AnalysisDriver, AnalysisDriverScheduler;
import 'package:analyzer/src/dart/analysis/driver.dart';
import 'package:analyzer/src/dart/analysis/file_state.dart';
import 'package:analyzer/src/dart/analysis/performance_logger.dart';
import 'package:analyzer/src/generated/engine.dart';
import 'package:analyzer/src/generated/sdk.dart';
import 'package:analyzer/src/generated/source.dart';
import 'package:analyzer/src/generated/source_io.dart';
import 'package:angular_analyzer_plugin/notification_manager.dart';
import 'package:angular_analyzer_plugin/src/angular_driver.dart';
import 'package:angular_analyzer_plugin/src/model.dart';
import 'package:angular_analyzer_plugin/src/options.dart';
import 'package:angular_analyzer_plugin/src/selector.dart';
import 'package:angular_analyzer_plugin/src/tuple.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'mock_angular.dart';
import 'mock_sdk.dart';

void assertComponentReference(
    ResolvedRange resolvedRange, Component component) {
  final selector = component.selector as ElementNameSelector;
  final element = resolvedRange.element;
  expect(element, selector.nameElement);
  expect(resolvedRange.range.length, selector.nameElement.name.length);
}

PropertyAccessorElement assertGetter(ResolvedRange resolvedRange) {
  final element =
      (resolvedRange.element as DartElement).element as PropertyAccessorElement;
  expect(element.isGetter, isTrue);
  return element;
}

void assertPropertyReference(
    ResolvedRange resolvedRange, AbstractDirective directive, String name) {
  final element = resolvedRange.element;
  for (final input in directive.inputs) {
    if (input.name == name) {
      expect(element, same(input));
      return;
    }
  }
  fail('Expected input "$name", but $element found.');
}

Component getComponentByName(List<AbstractDirective> directives, String name) =>
    getDirectiveByName(directives, name) as Component;

AbstractDirective getDirectiveByName(
        List<AbstractDirective> directives, String name) =>
    directives.firstWhere((directive) => directive.name == name, orElse: () {
      fail('DirectiveMetadata with the class "$name" was not found.');
    });

ResolvedRange getResolvedRangeAtString(
    String code, List<ResolvedRange> ranges, String str,
    [ResolvedRangeCondition condition]) {
  final offset = code.indexOf(str);
  return ranges.firstWhere((range) {
    if (range.range.offset == offset) {
      return condition == null || condition(range);
    }
    return false;
  }, orElse: () {
    fail(
        'ResolvedRange at $offset of $str was not found in [\n${ranges.join('\n')}]');
  });
}

View getViewByClassName(List<View> views, String className) =>
    views.firstWhere((view) => view.classElement.name == className, orElse: () {
      fail('View with the class "$className" was not found.');
    });

typedef bool ResolvedRangeCondition(ResolvedRange range);

class AbstractAngularTest {
  MemoryResourceProvider resourceProvider;

  DartSdk sdk;
  AngularDriver angularDriver;
  AnalysisDriver dartDriver;
  AnalysisDriverScheduler scheduler;

  GatheringErrorListener errorListener;

  AngularOptions ngOptions = new AngularOptions(
      customTagNames: [
        'my-first-custom-tag',
        'my-second-custom-tag'
      ],
      customEvents: {
        'custom-event': new CustomEvent('custom-event', 'CustomEvent',
            'package:test_package/custom_event.dart', 10)
      },
      source: () {
        final mock = new MockSource();
        when(mock.fullName).thenReturn('/analysis_options.yaml');
        return mock;
      }());

  // flags specific to handling multiple versions of angular which may differ,
  // but we still need to support.
  final bool includeQueryList;

  AbstractAngularTest() : includeQueryList = true;
  AbstractAngularTest.future() : includeQueryList = false;

  /// Assert that the [errCode] is reported for [code], highlighting the
  /// [snippet]. Optionally, expect [additionalErrorCodes] to appear at any
  /// location.
  void assertErrorInCodeAtPosition(
      ErrorCode errCode, String code, String snippet,
      {List<ErrorCode> additionalErrorCodes}) {
    final snippetIndex = code.indexOf(snippet);
    expect(snippetIndex, greaterThan(-1),
        reason: 'Error in test: snippet $snippet not part of code $code');
    final expectedErrorCodes = (additionalErrorCodes ?? <ErrorCode>[])
      ..add(errCode);
    errorListener.assertErrorsWithCodes(expectedErrorCodes);
    final error =
        errorListener.errors.singleWhere((e) => e.errorCode == errCode);
    expect(error.offset, snippetIndex);
    expect(error.length, snippet.length);
  }

  /// For [expectedErrors], it is a List of Tuple4 (1 per error):
  ///   code segment where offset begins,
  ///   length of error highlight,
  ///   errorCode,
  ///   and optional error args - pass empty list if not needed.
  void assertMultipleErrorsExplicit(
    Source source,
    String code,
    List<Tuple4<String, int, ErrorCode, List<Object>>> expectedErrors,
  ) {
    final realErrors = errorListener.errors;
    for (final expectedError in expectedErrors) {
      final offset = code.indexOf(expectedError.item1);
      assert(offset != -1);
      final currentExpectedError = new AnalysisError(
        source,
        offset,
        expectedError.item2,
        expectedError.item3,
        expectedError.item4,
      );
      expect(
        realErrors.contains(currentExpectedError),
        true,
        reason: 'Expected error code ${expectedError.item3} never occurs at '
            'location $offset of length ${expectedError.item2}.',
      );
      expect(realErrors.length, expectedErrors.length,
          reason: 'Expected error counts do not  match.');
    }
  }

  void fillErrorListener(List<AnalysisError> errors) {
    errorListener.addAll(errors);
  }

  Source newSource(String path, [String content = '']) {
    final file = resourceProvider.newFile(path, content);
    final source = file.createSource();
    angularDriver.addFile(path);
    dartDriver.addFile(path);
    return source;
  }

  void setUp() {
    final logger = new PerformanceLog(new StringBuffer());
    final byteStore = new MemoryByteStore();

    scheduler = new AnalysisDriverScheduler(logger)..start();
    resourceProvider = new MemoryResourceProvider();

    sdk = new MockSdk(resourceProvider: resourceProvider);
    final packageMap = <String, List<Folder>>{
      'angular2': [resourceProvider.getFolder('/angular2')],
      'angular': [resourceProvider.getFolder('/angular')],
      'test_package': [resourceProvider.getFolder('/')],
    };
    final packageResolver =
        new PackageMapUriResolver(resourceProvider, packageMap);
    final sf = new SourceFactory([
      new DartUriResolver(sdk),
      packageResolver,
      new ResourceUriResolver(resourceProvider)
    ]);
    final testPath = resourceProvider.convertPath('/test');
    final contextRoot = new ContextRoot(testPath, [],
        pathContext: resourceProvider.pathContext);

    dartDriver = new AnalysisDriver(
        new AnalysisDriverScheduler(logger)..start(),
        logger,
        resourceProvider,
        byteStore,
        new FileContentOverlay(),
        contextRoot,
        sf,
        new AnalysisOptionsImpl());
    angularDriver = new AngularDriver(
        resourceProvider,
        new MockNotificationManager(),
        dartDriver,
        scheduler,
        byteStore,
        sf,
        new FileContentOverlay(),
        ngOptions);

    errorListener = new GatheringErrorListener();
    addAngularSources(newSource, includeQueryList: includeQueryList);
  }
}

/// Instances of the class [GatheringErrorListener] implement an error listener
/// that collects all of the errors passed to it for later examination.
class GatheringErrorListener implements AnalysisErrorListener {
  /// A list containing the errors that were collected.
  final errors = <AnalysisError>[];

  /// Add all of the given errors to this listener.
  void addAll(List<AnalysisError> errors) {
    for (final error in errors) {
      onError(error);
    }
  }

  /// Assert that the number of errors that have been gathered matches the number
  /// of errors that are given and that they have the expected error codes. The
  /// order in which the errors were gathered is ignored.
  void assertErrorsWithCodes(
      [List<ErrorCode> expectedErrorCodes = const <ErrorCode>[]]) {
    final buffer = new StringBuffer();
    //
    // Verify that the expected error codes have a non-empty message.
    //
    for (final errorCode in expectedErrorCodes) {
      expect(errorCode.message.isEmpty, isFalse,
          reason: "Empty error code message");
    }
    //
    // Compute the expected number of each type of error.
    //
    final expectedCounts = <ErrorCode, int>{};
    for (final code in expectedErrorCodes) {
      var count = expectedCounts[code];
      if (count == null) {
        count = 1;
      } else {
        count = count + 1;
      }
      expectedCounts[code] = count;
    }
    //
    // Compute the actual number of each type of error.
    //
    final errorsByCode = <ErrorCode, List<AnalysisError>>{};
    for (final error in errors) {
      final code = error.errorCode;
      var list = errorsByCode[code];
      if (list == null) {
        list = <AnalysisError>[];
        errorsByCode[code] = list;
      }
      list.add(error);
    }
    //
    // Compare the expected and actual number of each type of error.
    //
    expectedCounts.forEach((code, expectedCount) {
      int actualCount;
      final list = errorsByCode.remove(code);
      if (list == null) {
        actualCount = 0;
      } else {
        actualCount = list.length;
      }
      if (actualCount != expectedCount) {
        if (buffer.length == 0) {
          buffer.write("Expected ");
        } else {
          buffer.write("; ");
        }
        buffer
          ..write(expectedCount)
          ..write(" errors of type ")
          ..write(code.uniqueName)
          ..write(", found ")
          ..write(actualCount);
      }
    });
    //
    // Check that there are no more errors in the actual-errors map,
    // otherwise record message.
    //
    errorsByCode.forEach((code, actualErrors) {
      final actualCount = actualErrors.length;
      if (buffer.isEmpty) {
        buffer.write("Expected ");
      } else {
        buffer.write("; ");
      }
      buffer
        ..write("0 errors of type ")
        ..write(code.uniqueName)
        ..write(", found ")
        ..write(actualCount)
        ..write(" (");
      for (var i = 0; i < actualErrors.length; i++) {
        final error = actualErrors[i];
        if (i > 0) {
          buffer.write(", ");
        }
        buffer.write(error.offset);
      }
      buffer.write(")");
    });
    if (buffer.length > 0) {
      fail(buffer.toString());
    }
  }

  /// Assert that no errors have been gathered.
  void assertNoErrors() {
    assertErrorsWithCodes();
  }

  @override
  void onError(AnalysisError error) {
    errors.add(error);
  }
}

class MockNotificationManager extends Mock implements NotificationManager {}

class MockSource extends Mock implements Source {}
