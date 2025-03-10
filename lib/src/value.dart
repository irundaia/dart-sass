// Copyright 2016 Google Inc. Use of this source code is governed by an
// MIT-style license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'package:meta/meta.dart';

import 'ast/selector.dart';
import 'exception.dart';
import 'value/boolean.dart';
import 'value/color.dart';
import 'value/external/value.dart' as ext;
import 'value/function.dart';
import 'value/list.dart';
import 'value/map.dart';
import 'value/number.dart';
import 'value/string.dart';
import 'visitor/interface/value.dart';
import 'visitor/serialize.dart';

export 'value/argument_list.dart';
export 'value/boolean.dart';
export 'value/color.dart';
export 'value/function.dart';
export 'value/list.dart';
export 'value/map.dart';
export 'value/null.dart';
export 'value/number.dart';
export 'value/string.dart';

// TODO(nweiz): Just mark members as @internal when sdk#28066 is fixed.
/// The implementation of [ext.Value].
///
/// This is a separate class to avoid exposing more API surface than necessary
/// to users outside this package.
abstract class Value implements ext.Value {
  bool get isTruthy => true;
  ListSeparator get separator => ListSeparator.undecided;
  bool get hasBrackets => false;
  List<Value> get asList => [this];

  /// The length of [asList].
  ///
  /// This is used to compute [sassIndexToListIndex] without allocating a new
  /// list.
  @protected
  int get lengthAsList => 1;

  /// Whether the value will be represented in CSS as the empty string.
  bool get isBlank => false;

  /// Whether this is a value that CSS may treat as a number, such as `calc()`
  /// or `var()`.
  ///
  /// Functions that shadow plain CSS functions need to gracefully handle when
  /// these arguments are passed in.
  bool get isSpecialNumber => false;

  /// Whether this is a call to `var()`, which may be substituted in CSS for a
  /// custom property value.
  ///
  /// Functions that shadow plain CSS functions need to gracefully handle when
  /// these arguments are passed in.
  bool get isVar => false;

  /// Returns Dart's `null` value if this is [sassNull], and returns [this]
  /// otherwise.
  Value? get realNull => this;

  const Value();

  /// Calls the appropriate visit method on [visitor].
  ///
  /// **Note:** this function should not be called outside the `sass` package.
  /// It's not guaranteed to be stable across versions.
  T accept<T>(ValueVisitor<T> visitor);

  int sassIndexToListIndex(ext.Value sassIndex, [String? name]) {
    var index = sassIndex.assertNumber(name).assertInt(name);
    if (index == 0) throw _exception("List index may not be 0.", name);
    if (index.abs() > lengthAsList) {
      throw _exception(
          "Invalid index $sassIndex for a list with $lengthAsList elements.",
          name);
    }

    return index < 0 ? lengthAsList + index : index - 1;
  }

  SassBoolean assertBoolean([String? name]) =>
      throw _exception("$this is not a boolean.", name);

  SassColor assertColor([String? name]) =>
      throw _exception("$this is not a color.", name);

  SassFunction assertFunction([String? name]) =>
      throw _exception("$this is not a function reference.", name);

  SassMap assertMap([String? name]) =>
      throw _exception("$this is not a map.", name);

  SassMap? tryMap() => null;

  SassNumber assertNumber([String? name]) =>
      throw _exception("$this is not a number.", name);

  SassString assertString([String? name]) =>
      throw _exception("$this is not a string.", name);

  /// Parses [this] as a selector list, in the same manner as the
  /// `selector-parse()` function.
  ///
  /// Throws a [SassScriptException] if this isn't a type that can be parsed as a
  /// selector, or if parsing fails. If [allowParent] is `true`, this allows
  /// [ParentSelector]s. Otherwise, they're considered parse errors.
  ///
  /// If this came from a function argument, [name] is the argument name
  /// (without the `$`). It's used for error reporting.
  SelectorList assertSelector({String? name, bool allowParent = false}) {
    var string = _selectorString(name);
    try {
      return SelectorList.parse(string, allowParent: allowParent);
    } on SassFormatException catch (error) {
      // TODO(nweiz): colorize this if we're running in an environment where
      // that works.
      throw _exception(error.toString().replaceFirst("Error: ", ""), name);
    }
  }

  /// Parses [this] as a simple selector, in the same manner as the
  /// `selector-parse()` function.
  ///
  /// Throws a [SassScriptException] if this isn't a type that can be parsed as a
  /// selector, or if parsing fails. If [allowParent] is `true`, this allows
  /// [ParentSelector]s. Otherwise, they're considered parse errors.
  ///
  /// If this came from a function argument, [name] is the argument name
  /// (without the `$`). It's used for error reporting.
  SimpleSelector assertSimpleSelector(
      {String? name, bool allowParent = false}) {
    var string = _selectorString(name);
    try {
      return SimpleSelector.parse(string, allowParent: allowParent);
    } on SassFormatException catch (error) {
      // TODO(nweiz): colorize this if we're running in an environment where
      // that works.
      throw _exception(error.toString().replaceFirst("Error: ", ""), name);
    }
  }

  /// Parses [this] as a compound selector, in the same manner as the
  /// `selector-parse()` function.
  ///
  /// Throws a [SassScriptException] if this isn't a type that can be parsed as a
  /// selector, or if parsing fails. If [allowParent] is `true`, this allows
  /// [ParentSelector]s. Otherwise, they're considered parse errors.
  ///
  /// If this came from a function argument, [name] is the argument name
  /// (without the `$`). It's used for error reporting.
  CompoundSelector assertCompoundSelector(
      {String? name, bool allowParent = false}) {
    var string = _selectorString(name);
    try {
      return CompoundSelector.parse(string, allowParent: allowParent);
    } on SassFormatException catch (error) {
      // TODO(nweiz): colorize this if we're running in an environment where
      // that works.
      throw _exception(error.toString().replaceFirst("Error: ", ""), name);
    }
  }

  /// Converts a `selector-parse()`-style input into a string that can be
  /// parsed.
  ///
  /// Throws a [SassScriptException] if [this] isn't a type or a structure that
  /// can be parsed as a selector.
  String _selectorString([String? name]) {
    var string = _selectorStringOrNull();
    if (string != null) return string;

    throw _exception(
        "$this is not a valid selector: it must be a string,\n"
        "a list of strings, or a list of lists of strings.",
        name);
  }

  /// Converts a `selector-parse()`-style input into a string that can be
  /// parsed.
  ///
  /// Returns `null` if [this] isn't a type or a structure that can be parsed as
  /// a selector.
  String? _selectorStringOrNull() {
    if (this is SassString) return (this as SassString).text;
    if (this is! SassList) return null;
    var list = this as SassList;
    if (list.asList.isEmpty) return null;

    var result = <String>[];
    switch (list.separator) {
      case ListSeparator.comma:
        for (var complex in list.asList) {
          if (complex is SassString) {
            result.add(complex.text);
          } else if (complex is SassList &&
              complex.separator == ListSeparator.space) {
            var string = complex._selectorStringOrNull();
            if (string == null) return null;
            result.add(string);
          } else {
            return null;
          }
        }
        break;
      case ListSeparator.slash:
        return null;
      default:
        for (var compound in list.asList) {
          if (compound is SassString) {
            result.add(compound.text);
          } else {
            return null;
          }
        }
        break;
    }
    return result.join(list.separator == ListSeparator.comma ? ', ' : ' ');
  }

  /// Returns a new list containing [contents] that defaults to this value's
  /// separator and brackets.
  SassList changeListContents(Iterable<Value> contents,
      {ListSeparator? separator, bool? brackets}) {
    return SassList(contents, separator ?? this.separator,
        brackets: brackets ?? hasBrackets);
  }

  /// The SassScript `=` operation.
  ///
  /// **Note:** this function should not be called outside the `sass` package.
  /// It's not guaranteed to be stable across versions.
  Value singleEquals(Value other) =>
      SassString("${toCssString()}=${other.toCssString()}", quotes: false);

  /// The SassScript `>` operation.
  ///
  /// **Note:** this function should not be called outside the `sass` package.
  /// It's not guaranteed to be stable across versions.
  SassBoolean greaterThan(Value other) =>
      throw SassScriptException('Undefined operation "$this > $other".');

  /// The SassScript `>=` operation.
  ///
  /// **Note:** this function should not be called outside the `sass` package.
  /// It's not guaranteed to be stable across versions.
  SassBoolean greaterThanOrEquals(Value other) =>
      throw SassScriptException('Undefined operation "$this >= $other".');

  /// The SassScript `<` operation.
  ///
  /// **Note:** this function should not be called outside the `sass` package.
  /// It's not guaranteed to be stable across versions.
  SassBoolean lessThan(Value other) =>
      throw SassScriptException('Undefined operation "$this < $other".');

  /// The SassScript `<=` operation.
  ///
  /// **Note:** this function should not be called outside the `sass` package.
  /// It's not guaranteed to be stable across versions.
  SassBoolean lessThanOrEquals(Value other) =>
      throw SassScriptException('Undefined operation "$this <= $other".');

  /// The SassScript `*` operation.
  ///
  /// **Note:** this function should not be called outside the `sass` package.
  /// It's not guaranteed to be stable across versions.
  Value times(Value other) =>
      throw SassScriptException('Undefined operation "$this * $other".');

  /// The SassScript `%` operation.
  ///
  /// **Note:** this function should not be called outside the `sass` package.
  /// It's not guaranteed to be stable across versions.
  Value modulo(Value other) =>
      throw SassScriptException('Undefined operation "$this % $other".');

  /// The SassScript `+` operation.
  ///
  /// **Note:** this function should not be called outside the `sass` package.
  /// It's not guaranteed to be stable across versions.
  Value plus(Value other) {
    if (other is SassString) {
      return SassString(toCssString() + other.text, quotes: other.hasQuotes);
    } else {
      return SassString(toCssString() + other.toCssString(), quotes: false);
    }
  }

  /// The SassScript `-` operation.
  ///
  /// **Note:** this function should not be called outside the `sass` package.
  /// It's not guaranteed to be stable across versions.
  Value minus(Value other) =>
      SassString("${toCssString()}-${other.toCssString()}", quotes: false);

  /// The SassScript `/` operation.
  ///
  /// **Note:** this function should not be called outside the `sass` package.
  /// It's not guaranteed to be stable across versions.
  Value dividedBy(Value other) =>
      SassString("${toCssString()}/${other.toCssString()}", quotes: false);

  /// The SassScript unary `+` operation.
  ///
  /// **Note:** this function should not be called outside the `sass` package.
  /// It's not guaranteed to be stable across versions.
  Value unaryPlus() => SassString("+${toCssString()}", quotes: false);

  /// The SassScript unary `-` operation.
  ///
  /// **Note:** this function should not be called outside the `sass` package.
  /// It's not guaranteed to be stable across versions.
  Value unaryMinus() => SassString("-${toCssString()}", quotes: false);

  /// The SassScript unary `/` operation.
  ///
  /// **Note:** this function should not be called outside the `sass` package.
  /// It's not guaranteed to be stable across versions.
  Value unaryDivide() => SassString("/${toCssString()}", quotes: false);

  /// The SassScript unary `not` operation.
  ///
  /// **Note:** this function should not be called outside the `sass` package.
  /// It's not guaranteed to be stable across versions.
  Value unaryNot() => sassFalse;

  /// Returns a copy of [this] without [SassNumber.asSlash] set.
  ///
  /// If this isn't a [SassNumber], returns it as-is.
  ///
  /// **Note:** this function should not be called outside the `sass` package.
  /// It's not guaranteed to be stable across versions.
  Value withoutSlash() => this;

  /// Returns a valid CSS representation of [this].
  ///
  /// Throws a [SassScriptException] if [this] can't be represented in plain
  /// CSS. Use [toString] instead to get a string representation even if this
  /// isn't valid CSS.
  ///
  /// If [quote] is `false`, quoted strings are emitted without quotes.
  String toCssString({bool quote = true}) => serializeValue(this, quote: quote);

  String toString() => serializeValue(this, inspect: true);

  /// Throws a [SassScriptException] with the given [message].
  SassScriptException _exception(String message, [String? name]) =>
      SassScriptException(name == null ? message : "\$$name: $message");
}
