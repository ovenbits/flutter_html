import 'dart:ui';

import 'package:csslib/parser.dart' as cssparser;
import 'package:csslib/visitor.dart';
import 'package:flutter_html/src/styled_element.dart';
import 'package:flutter_html/style.dart';
import 'package:html/src/query_selector.dart';
import 'package:flutter/widgets.dart';

Map<String, Style> cssToStyles(StyleSheet sheet) {
  sheet.topLevels.forEach((treeNode) {
    if (treeNode is RuleSet) {
      print(
          treeNode.selectorGroup.selectors.first.simpleSelectorSequences.first.simpleSelector.name);
    }
  });
}

class DeclarationVisitor extends Visitor {
  final StyledElement element;
  final bool isInline;

  String _currentProperty;

  DeclarationVisitor({this.element, this.isInline = false}) {
    // print('\nDeclarationVisitor(<${element?.name} id="${element?.elementId}" class="${element?.elementClasses?.join(' ')}" ${element?.attributes?.entries?.map((entry) => '[${entry.key}=${entry.value}]')?.join(' ')}');
  }

  void applyDeclarations(StyleSheet sheet) {
    sheet.visit(this);
  }

  @override
  void visitRuleSet(RuleSet node) {
    // print('visitRuleSet(${node.span.text})');
    if (element == null || (element.element != null && matches(element.element, node.span.text))) {
      visitDeclarationGroup(node.declarationGroup);
    }
  }

  @override
  void visitDeclaration(Declaration node) {
    // print('visitDeclaration(${node.span.text})');
    _currentProperty = node.property;
    node.expression.visit(this);
    node.dartStyle?.visit(this);
  }

  @override
  void visitExpressions(Expressions node) {
    // print('visitExpressions(${node.span.text})');
    node.expressions.forEach((expression) {
      expression.visit(this);
      //_result[_currentProperty].add(expression);
    });
  }

  @override
  void visitLiteralTerm(LiteralTerm node) {
    // print('visitLiteralTerm(${node.span.text})');
    switch (_currentProperty) {
      case 'direction':
        element.style.direction = ExpressionMapping.expressionToDirection(node);
        break;
      case 'display':
        element.style.display = ExpressionMapping.expressionToDisplay(node);
        break;
    }
  }

  @override
  void visitHexColorTerm(HexColorTerm node) {
    // print('visitHexColorTerm');
    switch (_currentProperty) {
      case 'background-color':
        element.style.backgroundColor = ExpressionMapping.expressionToColor(node);
        break;
      case 'color':
        element.style.color = ExpressionMapping.expressionToColor(node);
        break;
    }
  }

  @override
  void visitFontExpression(FontExpression node) {
    // print('visitFontExpression(${node.span.text})');
    element.style.fontFamily = node.span.text;
  }
  
  @override
  void visitBoxExpression(BoxExpression node) {
    // print('visitBoxExpression(${node.span.text})');
  }

  @override
  void visitMarginExpression(MarginExpression node) {
    // print('visitMarginExpression(${node.span.text})');
  }

  @override
  void visitBorderExpression(BorderExpression node) {
    // print('visitBorderExpression(${node.span.text})');
  }

  @override
  void visitHeightExpression(HeightExpression node) {
    // print('visitHeightExpression(${node.span.text})');
  }

  @override
  void visitPaddingExpression(PaddingExpression node) {
    // print('visitPaddingExpression(${node.span.text})');
    final box = node.box;
    element.style.padding = EdgeInsets.fromLTRB(box.left.toDouble(), box.top.toDouble(), box.right.toDouble(), box.bottom.toDouble());
  }

  @override
  void visitWidthExpression(WidthExpression node) {
    print('visitWidthExpression(${node.span.text})');
  }
}

//Mapping functions
class ExpressionMapping {

  static Color expressionToColor(Expression value) {
    if (value is HexColorTerm) {
      return stringToColor(value.text);
    }
    //TODO(Sub6Resources): Support function-term values (rgba()/rgb())
    return null;
  }

  static Color stringToColor(String _text) {
    var text = _text.replaceFirst('#', '');
    if (text.length == 3)
      text = text.replaceAllMapped(
          RegExp(r"[a-f]|\d"), (match) => '${match.group(0)}${match.group(0)}');
    int color = int.parse(text, radix: 16);

    if (color <= 0xffffff) {
      return new Color(color).withAlpha(255);
    } else {
      return new Color(color);
    }
  }

  static TextAlign expressionToTextAlign(Expression value) {
    if (value is LiteralTerm) {
      switch (value.text) {
        case "center":
          return TextAlign.center;
        case "left":
          return TextAlign.left;
        case "right":
          return TextAlign.right;
        case "justify":
          return TextAlign.justify;
        case "end":
          return TextAlign.end;
        case "start":
          return TextAlign.start;
      }
    }
    return TextAlign.start;
  }

  static EdgeInsets expressionToPadding(Expression value) {
    if (value is PaddingExpression) {
      final box = (value as PaddingExpression).box;
      return EdgeInsets.fromLTRB(box.left, box.top, box.right, box.bottom);
    }
    return EdgeInsets.zero;
  }

  static TextDirection expressionToDirection(Expression value) {
    if (value is LiteralTerm) {
      switch (value.text) {
        case "ltr":
          return TextDirection.ltr;
        case "rtl":
          return TextDirection.rtl;
      }
    }
    return TextDirection.ltr;
  }

  static List<FontFeature> expressionToFontFeatureSettings(List<Expression> value) {
    //TODO
    return [];
  }

  static List<Shadow> expressionToTextShadow(List<Expression> value) {
    //TODO
    return [];
  }

  static Display expressionToDisplay(Expression value) {
    if (value is LiteralTerm) {
      switch (value.text) {
        case 'block':
          return Display.BLOCK;
        case 'inline-block':
          return Display.INLINE_BLOCK;
        case 'inline':
          return Display.INLINE;
        case 'list-item':
          return Display.LIST_ITEM;
      }
    }
  }

  static String expressionToFontFamily(Expression value) {
    if (value is LiteralTerm)
      return value.text;
  }
}


