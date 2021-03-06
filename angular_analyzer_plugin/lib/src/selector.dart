library angular2.src.analysis.analyzer_plugin.src.selector;

import 'dart:collection';

import 'package:analyzer/src/generated/source.dart';
import 'package:angular_analyzer_plugin/src/model.dart';
import 'package:angular_analyzer_plugin/src/strings.dart';
import 'package:meta/meta.dart';

const _attributeEqualsValueRegexStr = // comment here for formatting:
    r'(\^=|\*=|=)' // capture which type of '=' operator
    // include values. Don't capture here, they contain captures themselves.
    '(?:$_attributeNoQuoteValueRegexStr|$_attributeQuotedValueRegexStr)';

const _attributeNameRegexStr = r'[-\w]+|\*';

const _attributeNoQuoteValueRegexStr =
    r'''([^\]'"]*)''' // Capture anything but ']' or a quote.
    ;

const _attributeQuotedValueRegexStr = // comment here for formatting:
    r"'([^\]']*)'" // Capture the contents of a single quoted string
    r'|' // or
    r'"([^\]"]*)"' // Capture the contents of a double quoted string
    ;

const _attributeRegexStr = // comment here for formatting:
    r'\[' // begins with '['
    '($_attributeNameRegexStr)' // capture the attribute name
    '(?:$_attributeEqualsValueRegexStr)?' // non-capturing optional value
    r'\]' // ends with ']'
    ;

/// The [Selector] that matches all of the given [selectors].
class AndSelector extends Selector {
  final List<Selector> selectors;

  AndSelector(this.selectors);

  @override
  bool availableTo(ElementView element) =>
      selectors.every((selector) => selector.availableTo(element));

  @override
  List<AngularElement> getAttributes(ElementView element) =>
      selectors.expand((selector) => selector.getAttributes(element)).toList();

  @override
  SelectorMatch match(ElementView element, Template template) {
    // Invalid selector case, should NOT match all.
    if (selectors.isEmpty) {
      return SelectorMatch.NoMatch;
    }

    var onSuccess = SelectorMatch.NonTagMatch;
    for (final selector in selectors) {
      final theMatch = selector.match(element, null);
      if (theMatch == SelectorMatch.TagMatch) {
        onSuccess = theMatch;
      } else if (theMatch == SelectorMatch.NoMatch) {
        return SelectorMatch.NoMatch;
      }
    }
    for (final selector in selectors) {
      selector.match(element, template);
    }
    return onSuccess;
  }

  @override
  void recordElementNameSelectors(List<ElementNameSelector> recordingList) {
    selectors.forEach(
        (selector) => selector.recordElementNameSelectors(recordingList));
  }

  @override
  List<HtmlTagForSelector> refineTagSuggestions(
      List<HtmlTagForSelector> context) {
    for (final selector in selectors) {
      // ignore: parameter_assignments
      context = selector.refineTagSuggestions(context);
    }
    return context;
  }

  @override
  String toString() => selectors.join(' && ');
}

/// The [AttributeContainsSelector] that matches elements that have attributes
/// with the given name, and that attribute contains the value of the selector.
class AttributeContainsSelector extends AttributeSelectorBase {
  @override
  final AngularElement nameElement;
  final String value;

  AttributeContainsSelector(this.nameElement, this.value);

  @override
  bool matchValue(String attributeValue) => attributeValue.contains(value);

  @override
  List<HtmlTagForSelector> refineTagSuggestions(
      List<HtmlTagForSelector> context) {
    for (final tag in context) {
      tag.setAttribute(nameElement.name, value: value);
    }
    return context;
  }

  @override
  String toString() {
    final name = nameElement.name;
    return '[$name*=$value]';
  }
}

/// The [Selector] that matches elements that have an attribute with the
/// given name, and (optionally) with the given value;
class AttributeSelector extends AttributeSelectorBase {
  @override
  final AngularElement nameElement;
  final String value;

  AttributeSelector(this.nameElement, this.value);

  @override
  List<AngularElement> getAttributes(ElementView element) =>
      match(element, null) == SelectorMatch.NonTagMatch ? [] : [nameElement];

  @override
  bool matchValue(String attributeValue) =>
      value == null || attributeValue == value;

  @override
  List<HtmlTagForSelector> refineTagSuggestions(
      List<HtmlTagForSelector> context) {
    for (final tag in context) {
      tag.setAttribute(nameElement.name, value: value);
    }
    return context;
  }

  @override
  String toString() {
    final name = nameElement.name;
    if (value != null) {
      return '[$name=$value]';
    }
    return '[$name]';
  }
}

abstract class AttributeSelectorBase extends Selector {
  AngularElement get nameElement;

  @override
  bool availableTo(ElementView element) =>
      !element.attributes.keys.contains(findAttribute(element)) ||
      match(element, null) != SelectorMatch.NoMatch;

  String findAttribute(ElementView element) => nameElement.name;

  @override
  List<AngularElement> getAttributes(ElementView element) =>
      element.attributes.keys.contains(findAttribute(element))
          ? []
          : [nameElement];

  @override
  SelectorMatch match(ElementView element, Template template) {
    SourceRange attributeSpan;
    String attributeValue;

    // Different selectors may find attributes differently
    final matchedName = findAttribute(element);
    if (matchedName == null) {
      return SelectorMatch.NoMatch;
    }

    attributeSpan = element.attributeNameSpans[matchedName];
    attributeValue = element.attributes[matchedName];

    if (attributeSpan == null) {
      return SelectorMatch.NoMatch;
    }

    // Different selectors may match the attribute value differently
    if (!matchValue(attributeValue)) {
      return SelectorMatch.NoMatch;
    }

    // OK
    if (template != null) {
      template.addRange(
          new SourceRange(attributeSpan.offset, attributeSpan.length),
          nameElement);
    }
    return SelectorMatch.NonTagMatch;
  }

  bool matchValue(String attributeValue);

  @override
  void recordElementNameSelectors(List<ElementNameSelector> recordingList) {
    // empty
  }
}

/// The [Selector] that matches elements that have an attribute with any name,
/// and with contents that match the given regex.
class AttributeStartsWithSelector extends AttributeSelectorBase {
  @override
  final AngularElement nameElement;

  final String value;

  AttributeStartsWithSelector(this.nameElement, this.value);

  @override
  bool matchValue(String attributeValue) => attributeValue.startsWith(value);

  @override
  List<HtmlTagForSelector> refineTagSuggestions(
          List<HtmlTagForSelector> context) =>
      context;

  @override
  String toString() => '[$nameElement^=$value]';
}

/// The [Selector] that matches elements that have an attribute with any name,
/// and with contents that match the given regex.
class AttributeValueRegexSelector extends Selector {
  final String regexpStr;
  final RegExp regexp;

  AttributeValueRegexSelector(this.regexpStr) : regexp = new RegExp(regexpStr);

  @override
  bool availableTo(ElementView element) =>
      match(element, null) == SelectorMatch.NonTagMatch;

  @override
  List<AngularElement> getAttributes(ElementView element) => [];

  @override
  SelectorMatch match(ElementView element, Template template) {
    for (final value in element.attributes.values) {
      if (regexp.hasMatch(value)) {
        return SelectorMatch.NonTagMatch;
      }
    }
    return SelectorMatch.NoMatch;
  }

  @override
  void recordElementNameSelectors(List<ElementNameSelector> recordingList) {
    // empty
  }

  @override
  List<HtmlTagForSelector> refineTagSuggestions(
          List<HtmlTagForSelector> context) =>
      context;

  @override
  String toString() => '[*=$regexpStr]';
}

/// The [Selector] that matches elements with the given (static) classes.
class ClassSelector extends Selector {
  final AngularElement nameElement;

  ClassSelector(this.nameElement);

  @override
  bool availableTo(ElementView element) => true;

  // Always return true - classes can always be added to satisfy without
  // having to remove or change existing classes.
  @override
  List<AngularElement> getAttributes(ElementView element) => [];

  @override
  SelectorMatch match(ElementView element, Template template) {
    final name = nameElement.name;
    final val = element.attributes['class'];
    // no 'class' attribute
    if (val == null) {
      return SelectorMatch.NoMatch;
    }
    // no such class
    if (!val.split(' ').contains(name)) {
      return SelectorMatch.NoMatch;
    }
    // prepare index of "name" int the "class" attribute value
    int index;
    if (val == name || val.startsWith('$name ')) {
      index = 0;
    } else if (val.endsWith(' $name')) {
      index = val.length - name.length;
    } else {
      index = val.indexOf(' $name ') + 1;
    }
    // add resolved range
    final valueOffset = element.attributeValueSpans['class'].offset;
    final offset = valueOffset + index;
    template?.addRange(new SourceRange(offset, name.length), nameElement);
    return SelectorMatch.NonTagMatch;
  }

  @override
  void recordElementNameSelectors(List<ElementNameSelector> recordingList) {
    // empty
  }

  @override
  List<HtmlTagForSelector> refineTagSuggestions(
      List<HtmlTagForSelector> context) {
    for (final tag in context) {
      tag.addClass(nameElement.name);
    }
    return context;
  }

  @override
  String toString() => '.${nameElement.name}';
}

/// The [Selector] that checks a TextNode for contents by a regex
class ContainsSelector extends Selector {
  final String regex;

  ContainsSelector(this.regex);

  @override
  bool availableTo(ElementView element) => false;

  @override
  List<AngularElement> getAttributes(ElementView element) => [];

  /// TODO check against actual text contents so we know which :contains
  /// directives were used (for when we want to advise removal of unused
  /// directives).
  ///
  /// We could also highlight the matching region in the text node with a color
  /// so users know it was applied.
  ///
  /// Not sure what else we could do.
  ///
  /// Never matches elements. Only matches [TextNode]s. Return false for now.
  @override
  SelectorMatch match(ElementView element, Template template) =>
      SelectorMatch.NoMatch;

  @override
  void recordElementNameSelectors(List<ElementNameSelector> recordingList) {
    // empty
  }

  @override
  List<HtmlTagForSelector> refineTagSuggestions(
          List<HtmlTagForSelector> context) =>
      context;

  @override
  String toString() => ":contains($regex)";
}

/// The element name based selector.
class ElementNameSelector extends Selector {
  final AngularElement nameElement;

  ElementNameSelector(this.nameElement);

  @override
  bool availableTo(ElementView element) =>
      nameElement.name == element.localName;

  @override
  List<AngularElement> getAttributes(ElementView element) => [];

  @override
  SelectorMatch match(ElementView element, Template template) {
    final name = nameElement.name;
    // match
    if (element.localName != name) {
      return SelectorMatch.NoMatch;
    }
    // done if no template
    if (template == null) {
      return SelectorMatch.TagMatch;
    }
    // record resolution
    if (element.openingNameSpan != null) {
      template.addRange(element.openingNameSpan, nameElement);
    }
    if (element.closingNameSpan != null) {
      template.addRange(element.closingNameSpan, nameElement);
    }
    return SelectorMatch.TagMatch;
  }

  @override
  void recordElementNameSelectors(List<ElementNameSelector> recordingList) {
    recordingList.add(this);
  }

  @override
  List<HtmlTagForSelector> refineTagSuggestions(
      List<HtmlTagForSelector> context) {
    for (final tag in context) {
      tag.name = nameElement.name;
    }
    return context;
  }

  @override
  String toString() => nameElement.name;
}

abstract class ElementView {
  Map<String, SourceRange> get attributeNameSpans;
  Map<String, String> get attributes;
  Map<String, SourceRange> get attributeValueSpans;
  SourceRange get closingNameSpan;
  SourceRange get closingSpan;
  String get localName;
  SourceRange get openingNameSpan;
  SourceRange get openingSpan;
}

/// Where possible it is good to be able to suggest a fully completed html tag to
/// match a selector. This has a few challenges: the selector may match multiple
/// things, it may not include any tag name to go off of at all. It may lend
/// itself to infinite suggestions (such as matching a regex), and parts of its
/// selector may cancel other parts out leading to invalid suggestions (such as
/// [prop=this][prop=thistoo]), especially in the presence of heavy booleans.
///
/// This doesn't track :not, so it may still suggest invalid things, but in
/// general the goal of this class is that its an empty shell which tracks
/// conflicting information.
///
/// Each selector takes in the current round of suggestions in
/// [refineTagSuggestions], and may return more suggestions than it got
/// originally (as in OR). At the end, all valid selectors can be checked for
/// validity.
///
/// Selector.suggestTags() handles creating a seed HtmlTagForSelector and
/// stripping invalid suggestions at the end, potentially resulting in none.
class HtmlTagForSelector {
  String _name;
  Map<String, String> _attributes = <String, String>{};
  bool _isValid = true;
  Set<String> _classes = new HashSet<String>();

  bool get isValid => _name != null && _isValid && _classAttrValid;

  String get name => _name;

  set name(String name) {
    if (_name != null && _name != name) {
      _isValid = false;
    } else {
      _name = name;
    }
  }

  bool get _classAttrValid => _classes.isEmpty || _attributes["class"] == null
      ? true
      : _classes.length == 1 && _classes.first == _attributes["class"];

  void addClass(String classname) {
    _classes.add(classname);
  }

  HtmlTagForSelector clone() => new HtmlTagForSelector()
    ..name = _name
    .._attributes = (<String, String>{}..addAll(_attributes))
    .._isValid = _isValid
    .._classes = new HashSet<String>.from(_classes);

  void setAttribute(String name, {String value}) {
    if (_attributes.containsKey(name)) {
      if (value != null) {
        if (_attributes[name] != null && _attributes[name] != value) {
          _isValid = false;
        } else {
          _attributes[name] = value;
        }
      }
    } else {
      _attributes[name] = value;
    }
  }

  @override
  String toString() {
    final keepClassAttr = _classes.isEmpty;

    final attrStrs = <String>[];
    _attributes.forEach((k, v) {
      // in the case of [class].myclass don't create multiple class attrs
      if (k != "class" || keepClassAttr) {
        attrStrs.add(v == null ? k : '$k="$v"');
      }
    });

    if (_classes.isNotEmpty) {
      final classesList = (<String>[]
            ..addAll(_classes)
            ..sort())
          .join(' ');
      attrStrs.add('class="$classesList"');
    }

    attrStrs.sort();

    return (['<$_name']..addAll(attrStrs)).join(' ');
  }
}

/// The [Selector] that confirms the inner [Selector] condition does NOT match
class NotSelector extends Selector {
  final Selector condition;

  NotSelector(this.condition);

  @override
  bool availableTo(ElementView element) =>
      condition.match(element, null) == SelectorMatch.NoMatch;

  @override
  List<AngularElement> getAttributes(ElementView element) => [];

  @override
  SelectorMatch match(ElementView element, Template template) =>
      condition.match(element, template) == SelectorMatch.NoMatch
          ? SelectorMatch.NonTagMatch
          : SelectorMatch.NoMatch;

  @override
  void recordElementNameSelectors(List<ElementNameSelector> recordingList) {
    // empty
  }

  @override
  List<HtmlTagForSelector> refineTagSuggestions(
          List<HtmlTagForSelector> context) =>
      context;

  @override
  String toString() => ":not($condition)";
}

/// The [Selector] that matches one of the given [selectors].
class OrSelector extends Selector {
  final List<Selector> selectors;

  OrSelector(this.selectors);

  @override
  bool availableTo(ElementView element) =>
      selectors.any((selector) => selector.availableTo(element));

  @override
  List<AngularElement> getAttributes(ElementView element) =>
      selectors.expand((selector) => selector.getAttributes(element)).toList();

  @override
  SelectorMatch match(ElementView element, Template template) {
    var onNoTagMatch = SelectorMatch.NoMatch;
    for (final selector in selectors) {
      final theMatch = selector.match(element, template);
      if (theMatch == SelectorMatch.TagMatch) {
        return SelectorMatch.TagMatch;
      } else if (theMatch == SelectorMatch.NonTagMatch) {
        onNoTagMatch = SelectorMatch.NonTagMatch;
      }
    }
    return onNoTagMatch;
  }

  @override
  void recordElementNameSelectors(List<ElementNameSelector> recordingList) {
    selectors.forEach(
        (selector) => selector.recordElementNameSelectors(recordingList));
  }

  @override
  List<HtmlTagForSelector> refineTagSuggestions(
      List<HtmlTagForSelector> context) {
    final response = <HtmlTagForSelector>[];
    for (final selector in selectors) {
      final newContext = context.map((t) => t.clone()).toList();
      response.addAll(selector.refineTagSuggestions(newContext));
    }

    return response;
  }

  @override
  String toString() => selectors.join(' || ');
}

/// The base class for all Angular selectors.
abstract class Selector {
  String originalString;
  int offset;

  /// Check whether the given [element] can potentially match with
  /// this selector. Or simply put, if there is no violation
  /// then the given [element] is 'availableTo' this selector without
  /// contradiction.
  ///
  /// Policy is 'availableTo' is true if selector can match
  /// without having to change/remove existing decorator.
  bool availableTo(ElementView element);

  /// Returns a list of all [AngularElement]s where each is an attribute name,
  /// and each attribute could be added to [element] and the selector would
  /// still be [availableTo] it.
  List<AngularElement> getAttributes(ElementView element);

  /// Check whether the given [element] matches this selector.
  /// If yes, then record resolved ranges into [template].
  SelectorMatch match(ElementView element, Template template);

  void recordElementNameSelectors(List<ElementNameSelector> recordingList);

  /// See [HtmlTagForSelector] for info on what this does.
  List<HtmlTagForSelector> refineTagSuggestions(
      List<HtmlTagForSelector> context);

  /// See [HtmlTagForSelector] for info on what this does. Selectors should NOT
  /// override this method, but rather [refineTagSuggestions].
  List<HtmlTagForSelector> suggestTags() {
    // create a seed tag: ORs will copy this, everything else modifies. Each
    // selector returns the newest set of tags to be transformed.
    final tags = [new HtmlTagForSelector()];
    return refineTagSuggestions(tags).where((t) => t.isValid).toList();
  }
} // chars with dash, may end with or be just '*'.

enum SelectorMatch { NoMatch, NonTagMatch, TagMatch }

/// A name that is a part of a [Selector].
class SelectorName extends AngularElementImpl {
  SelectorName(String name, int nameOffset, int nameLength, Source source)
      : super(name, nameOffset, nameLength, source);
}

class SelectorParseError extends FormatException {
  int length;
  SelectorParseError(String message, String source, int offset, this.length)
      : super(message, source, offset);
}

class SelectorParser {
  static const Map<int, _SelectorRegexMatch> matchIndexToType =
      const <int, _SelectorRegexMatch>{
    1: _SelectorRegexMatch.NotStart,
    2: _SelectorRegexMatch.Tag,
    3: _SelectorRegexMatch.Class,
    4: _SelectorRegexMatch.Attribute, // no quotes
    // 5 is part of Attribute. Not a match type.
    // 6 is part of Attribute. Not a match type.
    // 7 is part of Attribute. Not a match type.
    // 8 is part of Attribute. Not a match type.
    9: _SelectorRegexMatch.NotEnd,
    10: _SelectorRegexMatch.Comma,
    11: _SelectorRegexMatch.Contains,
    // 12 is a part of Contains.
  };
  static const _operatorMatch = 5;
  static const _unquotedValueMatch = 6;
  static const _singleQuotedValueMatch = 7;
  static const _doubleQuotedValueMatch = 8;
  Match currentMatch;
  Iterator<Match> matches;
  int lastOffset = 0;
  final int fileOffset;
  final String str;

  String currentMatchStr; // :contains doesn't mix with the rest

  _SelectorRegexMatch currentMatchType;

  int currentMatchIndex;
  final Source source;
  final RegExp _regExp = new RegExp(r'(\:not\()|'
      r'([-\w]+)|' // Tag
      r'(?:\.([-\w]+))|' // Class
      '(?:$_attributeRegexStr)|' // Attribute, in a non-capturing group.
      r'(\))|'
      r'(\s*,\s*)|'
      r'(^\:contains\(\/(.+)\/\)$)');
  SelectorParser(this.source, this.fileOffset, this.str);

  Match advance() {
    if (!matches.moveNext()) {
      currentMatch = null;
      return null;
    }

    currentMatch = matches.current;
    // no content should be skipped
    {
      final skipStr = str.substring(lastOffset, currentMatch.start);
      if (!isBlank(skipStr)) {
        _unexpected(skipStr, lastOffset + fileOffset);
      }
      lastOffset = currentMatch.end;
    }

    for (final index in matchIndexToType.keys) {
      if (currentMatch[index] != null) {
        currentMatchIndex = index;
        currentMatchType = matchIndexToType[index];
        currentMatchStr = currentMatch[index];
        return currentMatch;
      }
    }

    currentMatchType = null;
    currentMatchStr = null;
    return null;
  }

  Selector parse() {
    if (str == null) {
      return null;
    }
    matches = _regExp.allMatches(str).iterator;
    advance();
    final selector = parseNested();
    if (currentMatch != null) {
      _unexpected(
          currentMatchStr, fileOffset + (currentMatch?.start ?? lastOffset));
    }
    return selector
      ..originalString = str
      ..offset = fileOffset;
  }

  Selector parseNested() {
    final selectors = <Selector>[];
    while (currentMatch != null) {
      if (currentMatchType == _SelectorRegexMatch.NotEnd) {
        // don't advance, just know we're at the end of this And
        break;
      }

      if (currentMatchType == _SelectorRegexMatch.NotStart) {
        selectors.add(parseNotSelector());
      } else if (currentMatchType == _SelectorRegexMatch.Tag) {
        final nameOffset = fileOffset + currentMatch.start;
        final name = currentMatchStr;
        selectors.add(new ElementNameSelector(
            new SelectorName(name, nameOffset, name.length, source)));
        advance();
      } else if (currentMatchType == _SelectorRegexMatch.Class) {
        final nameOffset = fileOffset + currentMatch.start + 1;
        final name = currentMatchStr;
        selectors.add(new ClassSelector(
            new SelectorName(name, nameOffset, name.length, source)));
        advance();
      } else if (currentMatchType == _SelectorRegexMatch.Attribute) {
        final nameIndex = currentMatch.start + '['.length;
        final nameOffset = fileOffset + nameIndex;
        final operator = currentMatch[_operatorMatch];
        final value = currentMatch[_unquotedValueMatch] ??
            currentMatch[_singleQuotedValueMatch] ??
            currentMatch[_doubleQuotedValueMatch];

        if (operator != null && value.isEmpty) {
          _expected('a value after $operator',
              actual: ']', offset: currentMatch.end - 1);
        }

        var name = currentMatchStr;
        advance();

        if (name == '*' &&
            value != null &&
            value.startsWith('/') &&
            value.endsWith('/')) {
          if (operator != '=') {
            _unexpected(operator, nameIndex + name.length);
          }
          selectors.add(new AttributeValueRegexSelector(
              value.substring(1, value.length - 1)));
          continue;
        } else if (operator == '*=') {
          name = name.replaceAll('*', '');
          selectors.add(new AttributeContainsSelector(
              new SelectorName(name, nameOffset, name.length, source), value));
          continue;
        } else if (operator == '^=') {
          selectors.add(new AttributeStartsWithSelector(
              new SelectorName(name, nameOffset, name.length, source), value));
          continue;
        }

        selectors.add(new AttributeSelector(
            new SelectorName(name, nameOffset, name.length, source), value));
      } else if (currentMatchType == _SelectorRegexMatch.Comma) {
        advance();
        final rhs = parseNested();
        if (rhs is OrSelector) {
          // flatten "a, b, c, d" from (a, (b, (c, d))) into (a, b, c, d)
          return new OrSelector(
              <Selector>[_andSelectors(selectors)]..addAll(rhs.selectors));
        } else {
          return new OrSelector(<Selector>[_andSelectors(selectors), rhs]);
        }
      } else if (currentMatchType == _SelectorRegexMatch.Contains) {
        selectors
            .add(new ContainsSelector(currentMatch[currentMatchIndex + 1]));
        advance();
      } else {
        break;
      }
    }
    // final result
    return _andSelectors(selectors);
  }

  NotSelector parseNotSelector() {
    advance();
    final condition = parseNested();
    if (currentMatchType != _SelectorRegexMatch.NotEnd) {
      _unexpected(
          currentMatchStr, fileOffset + (currentMatch?.start ?? lastOffset));
    }
    advance();
    return new NotSelector(condition);
  }

  Selector _andSelectors(List<Selector> selectors) {
    if (selectors.length == 1) {
      return selectors[0];
    }
    return new AndSelector(selectors);
  }

  void _expected(String expected,
      {@required String actual, @required int offset}) {
    throw new SelectorParseError(
        "Expected $expected, got $actual", str, offset, actual.length);
  }

  void _unexpected(String eString, int eOffset) {
    throw new SelectorParseError(
        "Unexpected $eString", str, eOffset, eString.length);
  }
}

enum _SelectorRegexMatch {
  NotStart,
  NotEnd,
  Attribute,
  Tag,
  Comma,
  Class,
  Contains
}
