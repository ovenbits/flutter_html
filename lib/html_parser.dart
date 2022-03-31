import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:csslib/parser.dart' as cssparser;
import 'package:csslib/visitor.dart' as css;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_html/src/css_parser.dart';
import 'package:flutter_html/src/html_elements.dart';
import 'package:flutter_html/src/layout_element.dart';
import 'package:flutter_html/src/string_ext.dart';
import 'package:flutter_html/src/utils.dart';
import 'package:flutter_html/style.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as htmlparser;

typedef OnTap = void Function(String url);
typedef CustomRender = Widget Function(
  RenderContext context,
  Widget parsedChild,
  Map<String, String> attributes,
  dom.Element element,
);
typedef OnContentRendered = Function(Size size);

class HtmlParser extends StatefulWidget {
  const HtmlParser({
    Key key,
    this.htmlData,
    this.cssData,
    this.onLinkTap,
    this.onImageTap,
    this.onImageError,
    this.shrinkWrap,
    this.style,
    this.customRender,
    this.blacklistedElements,
    this.loadingPlaceholder,
    this.onContentRendered,
    this.textScaleMultiplier = 1.0,
  }) : super(key: key);

  final String htmlData;
  final String cssData;
  final OnTap onLinkTap;
  final OnTap onImageTap;
  final ImageErrorListener onImageError;
  final bool shrinkWrap;

  final Map<String, Style> style;
  final Map<String, CustomRender> customRender;
  final List<String> blacklistedElements;
  final Widget loadingPlaceholder;
  final OnContentRendered onContentRendered;
  final double textScaleMultiplier;

  @override
  _HtmlParserState createState() => _HtmlParserState();

  /// [parseHTML] converts a string of HTML to a DOM document using the dart `html` library.
  static dom.Document parseHTML(String data) {
    return htmlparser.parse(data);
  }

  /// [parseCSS] converts a string of CSS to a CSS stylesheet using the dart `csslib` library.
  static css.StyleSheet parseCSS(String data) {
    return cssparser.parse(data);
  }

  /// [lexDomTree] converts a DOM document to a simplified tree of [StyledElement]s.
  static StyledElement lexDomTree(dom.Document html, List<String> customRenderTags, List<String> blacklistedElements) {
    StyledElement tree = StyledElement(
      name: "[Tree Root]",
      children: new List<StyledElement>(),
      node: html.documentElement,
    );

    html.nodes.forEach((node) {
      tree.children.add(_recursiveLexer(node, customRenderTags, blacklistedElements));
    });

    return tree;
  }

  static StyledElement _lexDomTree(List args) {
    return lexDomTree(args[0], args[1], args[2]);
  }

  /// [_recursiveLexer] is the recursive worker function for [lexDomTree].
  ///
  /// It runs the parse functions of every type of
  /// element and returns a [StyledElement] tree representing the element.
  static StyledElement _recursiveLexer(
    dom.Node node,
    List<String> customRenderTags,
    List<String> blacklistedElements,
  ) {
    List<StyledElement> children = List<StyledElement>();

    node.nodes.forEach((childNode) {
      children.add(_recursiveLexer(childNode, customRenderTags, blacklistedElements));
    });

    //TODO(Sub6Resources): There's probably a more efficient way to look this up.
    if (node is dom.Element) {
      if (blacklistedElements?.contains(node.localName) ?? false) {
        return EmptyContentElement();
      }
      if (STYLED_ELEMENTS.contains(node.localName)) {
        return parseStyledElement(node, children);
      } else if (INTERACTABLE_ELEMENTS.contains(node.localName)) {
        return parseInteractableElement(node, children);
      } else if (REPLACED_ELEMENTS.contains(node.localName)) {
        return parseReplacedElement(node);
      } else if (LAYOUT_ELEMENTS.contains(node.localName)) {
        return parseLayoutElement(node, children);
      } else if (TABLE_STYLE_ELEMENTS.contains(node.localName)) {
        return parseTableDefinitionElement(node, children);
      } else if (customRenderTags.contains(node.localName)) {
        return parseStyledElement(node, children);
      } else {
        return EmptyContentElement();
      }
    } else if (node is dom.Text) {
      return TextContentElement(text: node.text);
    } else {
      return EmptyContentElement();
    }
  }

  ///TODO document
  static Future<StyledElement> applyCSS(List args) async {
    StyledElement tree = args[0];
    css.StyleSheet sheet = args[1];
    //Make sure style is never null.
    if (tree.style == null) {
      tree.style = Style();
    }

    // reset text/font properties to defaults
    tree.style.textAlign = TextAlign.start;
    tree.style.textDecoration = TextDecoration.none;
    tree.style.textIndent = 0;
    tree.style.fontStyle = FontStyle.normal;

    DeclarationVisitor(element: tree).applyDeclarations(sheet);
    tree.children?.forEach((e) => applyCSS([e, sheet]));

    return tree;
  }

  /// [applyInlineStyle] applies inline styles (i.e. `style="..."`) recursively into the StyledElement tree.
  static StyledElement applyInlineStyles(StyledElement tree) {
    if (tree.attributes.containsKey("style")) {
      final inlineStyle = tree.attributes['style'];
      final sheet = cssparser.parse("*{$inlineStyle}");
      DeclarationVisitor(element: tree, isInline: true).applyDeclarations(sheet);
    }

    tree.children?.forEach(applyInlineStyles);

    return tree;
  }

  /// [_cascadeStyles] cascades all of the inherited styles down the tree, applying them to each
  /// child that doesn't specify a different style.
  static StyledElement _cascadeStyles(StyledElement tree) {
    tree.children?.forEach((child) {
      child.style = tree.style.copyOnlyInherited(child.style);
      _cascadeStyles(child);
    });

    return tree;
  }

  /// [cleanTree] optimizes the [StyledElement] tree so all [BlockElement]s are
  /// on the first level, redundant levels are collapsed, empty elements are
  /// removed, and specialty elements are processed.
  static StyledElement cleanTree(StyledElement tree) {
    tree = _processInternalWhitespace(tree);
    tree = _processInlineWhitespace(tree);
    tree = _removeEmptyElements(tree);
    tree = _processListCharacters(tree);
    tree = _processBeforesAndAfters(tree);
    tree = _collapseMargins(tree);
    tree = _processFontSize(tree);
    tree = _processTextTransform(tree);
    return tree;
  }

//  static InlineSpan _computeParseTree(List args) {
//    return parseTree(args[0], args[1]);
//  }

  /// [parseTree] converts a tree of [StyledElement]s to an [InlineSpan] tree.
  ///
  /// [parseTree] is responsible for handling the [customRender] parameter and
  /// deciding what different `Style.display` options look like as Widgets.
  static Future<InlineSpan> parseTree(RenderContext context, StyledElement tree) async {
    // Merge this element's style into the context so that children
    // inherit the correct style
    RenderContext newContext = RenderContext(
      buildContext: context.buildContext,
      parser: context.parser,
      style: context.style.copyOnlyInherited(tree.style),
    );

    if (context.parser.customRender?.containsKey(tree.name) ?? false) {
      return WidgetSpan(
        child: ContainerSpan(
          newContext: newContext,
          style: tree.style,
          shrinkWrap: context.parser.shrinkWrap,
          child: context.parser.customRender[tree.name].call(
            newContext,
            ContainerSpan(
              newContext: newContext,
              style: tree.style,
              shrinkWrap: context.parser.shrinkWrap,
              children: await Future.wait(tree.children?.map((tree) => parseTree(newContext, tree))?.toList() ?? []),
            ),
            tree.attributes,
            tree.element,
          ),
        ),
      );
    }

    // Return the correct InlineSpan based on the element type.
    if (tree.style?.display == Display.BLOCK) {
      return WidgetSpan(
        child: ContainerSpan(
          newContext: newContext,
          style: tree.style,
          shrinkWrap: context.parser.shrinkWrap,
          children: await Future.wait(tree.children?.map((tree) => parseTree(newContext, tree))?.toList() ?? []),
        ),
      );
    } else if (tree.style?.display == Display.LIST_ITEM) {
      final List<InlineSpan> children = await Future.wait(tree.children.map((tree) => parseTree(newContext, tree)).toList());

      return WidgetSpan(
        child: ContainerSpan(
          newContext: newContext,
          style: tree.style,
          shrinkWrap: context.parser.shrinkWrap,
          child: Builder(
            builder: (context) => Stack(
              children: <Widget>[
                PositionedDirectional(
                  width: 30, //TODO derive this from list padding.
                  start: 0,
                  child: Text('${newContext.style.markerContent}\t', textAlign: TextAlign.right, style: newContext.style.generateTextStyle(context)),
                ),
                Padding(
                  padding: EdgeInsets.only(left: 30), //TODO derive this from list padding.
                  child: StyledText(
                    textSpan: TextSpan(
                      children: children,
                      style: newContext.style.generateTextStyle(context),
                    ),
                    style: newContext.style,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else if (tree is ReplacedElement) {
      if (tree is TextContentElement) {
        return TextSpan(text: tree.text);
      } else {
        return WidgetSpan(
          alignment: tree.alignment,
          baseline: TextBaseline.alphabetic,
          child: Builder(builder: (buildContext) => tree.toWidget(context)),
        );
      }
    } else if (tree is InteractableElement) {
      final List<InlineSpan> children = await Future.wait(tree.children.map((tree) => parseTree(newContext, tree)).toList());

      return WidgetSpan(
        child: RawGestureDetector(
          gestures: {
            MultipleTapGestureRecognizer: GestureRecognizerFactoryWithHandlers<MultipleTapGestureRecognizer>(
              () => MultipleTapGestureRecognizer(),
              (instance) {
                instance..onTap = () => context.parser.onLinkTap?.call(tree.href);
              },
            ),
          },
          child: Builder(
            builder: (context) => StyledText(
              textSpan: TextSpan(
                style: newContext.style.generateTextStyle(context),
                children: children,
              ),
              style: newContext.style,
            ),
          ),
        ),
      );
    } else if (tree is LayoutElement) {
      return WidgetSpan(
        child: await tree.toWidget(context),
      );
    } else if (tree.style.verticalAlign != null && tree.style.verticalAlign != VerticalAlign.BASELINE) {
      final List<InlineSpan> children = await Future.wait(tree.children.map((tree) => parseTree(newContext, tree)).toList());
      double verticalOffset;
      switch (tree.style.verticalAlign) {
        case VerticalAlign.SUB:
          verticalOffset = tree.style.fontSize.size / 2.5;
          break;
        case VerticalAlign.SUPER:
          verticalOffset = tree.style.fontSize.size / -2.5;
          break;
        default:
          break;
      }
      //Requires special layout features not available in the TextStyle API.
      return WidgetSpan(
        child: Transform.translate(
          offset: Offset(0, verticalOffset),
          child: Builder(
            builder: (context) => StyledText(
              textSpan: TextSpan(
                style: newContext.style.generateTextStyle(context),
                children: children,
              ),
              style: newContext.style,
            ),
          ),
        ),
      );
    } else {
      final List<InlineSpan> children = await Future.wait(tree.children.map((tree) => parseTree(newContext, tree)).toList());

      ///[tree] is an inline element.
      return WidgetSpan(
        child: Builder(
          builder: (context) => StyledText(
            style: newContext.style,
            textSpan: TextSpan(
              style: newContext.style.generateTextStyle(context),
              children: children,
            ),
          ),
        ),
      );
    }
  }

  /// [processWhitespace] removes unnecessary whitespace from the StyledElement tree.
  ///
  /// The criteria for determining which whitespace is replaceable is outlined
  /// at https://www.w3.org/TR/css-text-3/
  /// and summarized at https://medium.com/@patrickbrosset/when-does-white-space-matter-in-html-b90e8a7cdd33
  static StyledElement _processInternalWhitespace(StyledElement tree) {
    if ((tree.style?.whiteSpace ?? WhiteSpace.NORMAL) == WhiteSpace.PRE) {
      // Preserve this whitespace
    } else if (tree is TextContentElement) {
      tree.text = _removeUnnecessaryWhitespace(tree.text);
    } else {
      tree.children?.forEach(_processInternalWhitespace);
    }
    return tree;
  }

  /// [_processInlineWhitespace] is responsible for removing redundant whitespace
  /// between and among inline elements. It does so by creating a boolean [Context]
  /// and passing it to the [_processInlineWhitespaceRecursive] function.
  static StyledElement _processInlineWhitespace(StyledElement tree) {
    tree = _processInlineWhitespaceRecursive(tree, Context(false));
    return tree;
  }

  /// [_processInlineWhitespaceRecursive] analyzes the whitespace between and among different
  /// inline elements, and replaces any instance of two or more spaces with a single space, according
  /// to the w3's HTML whitespace processing specification linked to above.
  static StyledElement _processInlineWhitespaceRecursive(
      StyledElement tree,
      Context<bool> keepLeadingSpace,
      ) {
    if (tree is TextContentElement) {
      /// initialize indices to negative numbers to make conditionals a little easier
      int textIndex = -1;
      int elementIndex = -1;
      /// initialize parent after to a whitespace to account for elements that are
      /// the last child in the list of elements
      String parentAfterText = " ";
      /// find the index of the text in the current tree
      if ((tree.element?.nodes?.length ?? 0) >= 1) {
        textIndex = tree.element?.nodes?.indexWhere((element) => element == tree.element) ?? -1;
      }
      /// get the parent nodes
      dom.NodeList parentNodes = tree.element?.parent?.nodes;
      /// find the index of the tree itself in the parent nodes
      if ((parentNodes?.length ?? 0) >= 1) {
        elementIndex = parentNodes?.indexWhere((element) => element == tree.element) ?? -1;
      }
      /// if the tree is any node except the last node in the node list and the
      /// next node in the node list is a text node, then get its text. Otherwise
      /// the next node will be a [dom.Element], so keep unwrapping that until
      /// we get the underlying text node, and finally get its text.
      if (elementIndex < (parentNodes?.length ?? 1) - 1 && parentNodes != null && parentNodes[elementIndex + 1] is dom.Text) {
        parentAfterText = parentNodes[elementIndex + 1].text ?? " ";
      } else if (elementIndex < (parentNodes?.length ?? 1) - 1) {
        var parentAfter = parentNodes == null ? null : parentNodes[elementIndex + 1];
        while (parentAfter is dom.Element) {
          if (parentAfter.nodes.isNotEmpty) {
            parentAfter = parentAfter.nodes.first;
          } else {
            break;
          }
        }
        parentAfterText = parentAfter?.text ?? " ";
      }
      /// If the text is the first element in the current tree node list, it
      /// starts with a whitespace, it isn't a line break, either the
      /// whitespace is unnecessary or it is a block element, and either it is
      /// first element in the parent node list or the previous element
      /// in the parent node list ends with a whitespace, delete it.
      ///
      /// We should also delete the whitespace at any point in the node list
      /// if the previous element is a <br> because that tag makes the element
      /// act like a block element.
      if (textIndex < 1
          && tree.text.startsWith(' ')
          && tree.element?.localName != "br"
          && (!keepLeadingSpace.data
              || tree.style.display == Display.BLOCK)
          && (elementIndex < 1
              || (elementIndex >= 1
                  && parentNodes[elementIndex - 1] is dom.Text
                  && parentNodes[elementIndex - 1].text.endsWith(" ")))
      ) {
        tree.text = tree.text.replaceFirst(' ', '');
      } else if (textIndex >= 1
          && tree.text.startsWith(' ')
          && tree.element?.nodes[textIndex - 1] is dom.Element
          && (tree.element?.nodes[textIndex - 1] as dom.Element).localName == "br"
      ) {
        tree.text = tree.text.replaceFirst(' ', '');
      }
      /// If the text is the last element in the current tree node list, it isn't
      /// a line break, and the next text node starts with a whitespace,
      /// update the [Context] to signify to that next text node whether it should
      /// keep its whitespace. This is based on whether the current text ends with a
      /// whitespace.
      if (textIndex == (tree.element?.nodes?.length ?? 1) - 1
          && tree.element?.localName != "br"
          && parentAfterText.startsWith(' ')
      ) {
        keepLeadingSpace.data = !tree.text.endsWith(' ');
      }
    }

    tree.children?.forEach((e) => _processInlineWhitespaceRecursive(e, keepLeadingSpace));

    return tree;
  }

  /// [removeUnnecessaryWhitespace] removes "unnecessary" white space from the given String.
  ///
  /// The steps for removing this whitespace are as follows:
  /// (1) Remove any whitespace immediately preceding or following a newline.
  /// (2) Replace all newlines with a space
  /// (3) Replace all tabs with a space
  /// (4) Replace any instances of two or more spaces with a single space.
  static String _removeUnnecessaryWhitespace(String text) {
    print('"$text"');
    return text
        .replaceAll(RegExp("\ *(?=\n)"), "\n")
        .replaceAll(RegExp("(?:\n)\ *"), "\n")
        .replaceAll("\n", " ")
        .replaceAll("\t", " ")
        .replaceAll(RegExp(" {2,}"), " ");
  }

  /// [processListCharacters] adds list characters to the front of all list items.
  ///
  /// The function uses the [_processListCharactersRecursive] function to do most of its work.
  static StyledElement _processListCharacters(StyledElement tree) {
    final olStack = ListQueue<Context<int>>();
    tree = _processListCharactersRecursive(tree, olStack);
    return tree;
  }

  /// [_processListCharactersRecursive] uses a Stack of integers to properly number and
  /// bullet all list items according to the [ListStyleType] they have been given.
  static StyledElement _processListCharactersRecursive(StyledElement tree, ListQueue<Context<int>> olStack) {
    if (tree.name == 'ol') {
      olStack.add(Context(0));
    } else if (tree.style.display == Display.LIST_ITEM) {
      switch (tree.style.listStyleType) {
        case ListStyleType.DISC:
          tree.style.markerContent = '•';
          break;
        case ListStyleType.DECIMAL:
          olStack.last.data += 1;
          tree.style.markerContent = '${olStack.last.data}.';
      }
    }

    tree.children?.forEach((e) => _processListCharactersRecursive(e, olStack));

    if (tree.name == 'ol') {
      olStack.removeLast();
    }

    return tree;
  }

  /// [_processBeforesAndAfters] adds text content to the beginning and end of
  /// the list of the trees children according to the `before` and `after` Style
  /// properties.
  static StyledElement _processBeforesAndAfters(StyledElement tree) {
    if (tree.style?.before != null) {
      tree.children.insert(0, TextContentElement(text: tree.style.before));
    }
    if (tree.style?.after != null) {
      tree.children.add(TextContentElement(text: tree.style.after));
    }
    tree.children?.forEach(_processBeforesAndAfters);
    return tree;
  }

  /// [collapseMargins] follows the specifications at https://www.w3.org/TR/CSS21/box.html#collapsing-margins
  /// for collapsing margins of block-level boxes. This prevents the doubling of margins between
  /// boxes, and makes for a more correct rendering of the html content.
  ///
  /// Paraphrased from the CSS specification:
  /// Margins are collapsed if both belong to vertically-adjacent box edges, i.e form one of the following pairs:
  /// (1) Top margin of a box and top margin of its first in-flow child
  /// (2) Bottom margin of a box and top margin of its next in-flow following sibling
  /// (3) Bottom margin of a last in-flow child and bottom margin of its parent (if the parent's height is not explicit)
  /// (4) Top and Bottom margins of a box with a height of zero or no in-flow children.
  static StyledElement _collapseMargins(StyledElement tree) {
    //Short circuit if we've reached a leaf of the tree
    if (tree.children == null || tree.children.isEmpty) {
      // Handle case (4) from above.
      if ((tree.style.height ?? 0) == 0) {
        tree.style.margin = EdgeInsets.zero;
      }
      return tree;
    }

    //Collapsing should be depth-first.
    tree.children?.forEach(_collapseMargins);

    //The root boxes do not collapse.
    if (tree.name == '[Tree Root]' || tree.name == 'html') {
      return tree;
    }

    // Handle case (1) from above.
    // Top margins cannot collapse if the element has padding
    if ((tree.style.padding?.top ?? 0) == 0) {
      final parentTop = tree.style.margin?.top ?? 0;
      final firstChildTop = tree.children.first.style.margin?.top ?? 0;
      final newOuterMarginTop = max(parentTop, firstChildTop);

      // Set the parent's margin
      if (tree.style.margin == null) {
        tree.style.margin = EdgeInsets.only(top: newOuterMarginTop);
      } else {
        tree.style.margin = tree.style.margin.copyWith(top: newOuterMarginTop);
      }

      // And remove the child's margin
      if (tree.children.first.style.margin == null) {
        tree.children.first.style.margin = EdgeInsets.zero;
      } else {
        tree.children.first.style.margin = tree.children.first.style.margin.copyWith(top: 0);
      }
    }

    // Handle case (3) from above.
    // Bottom margins cannot collapse if the element has padding
    if ((tree.style.padding?.bottom ?? 0) == 0) {
      final parentBottom = tree.style.margin?.bottom ?? 0;
      final lastChildBottom = tree.children.last.style.margin?.bottom ?? 0;
      final newOuterMarginBottom = max(parentBottom, lastChildBottom);

      // Set the parent's margin
      if (tree.style.margin == null) {
        tree.style.margin = EdgeInsets.only(bottom: newOuterMarginBottom);
      } else {
        tree.style.margin = tree.style.margin.copyWith(bottom: newOuterMarginBottom);
      }

      // And remove the child's margin
      if (tree.children.last.style.margin == null) {
        tree.children.last.style.margin = EdgeInsets.zero;
      } else {
        tree.children.last.style.margin = tree.children.last.style.margin.copyWith(bottom: 0);
      }
    }

    // Handle case (2) from above.
    if (tree.children.length > 1) {
      for (int i = 1; i < tree.children.length; i++) {
        final previousSiblingBottom = tree.children[i - 1].style.margin?.bottom ?? 0;
        final thisTop = tree.children[i].style.margin?.top ?? 0;
        final newInternalMargin = max(previousSiblingBottom, thisTop) / 2;

        if (tree.children[i - 1].style.margin == null) {
          tree.children[i - 1].style.margin = EdgeInsets.only(bottom: newInternalMargin);
        } else {
          tree.children[i - 1].style.margin = tree.children[i - 1].style.margin.copyWith(bottom: newInternalMargin);
        }

        if (tree.children[i].style.margin == null) {
          tree.children[i].style.margin = EdgeInsets.only(top: newInternalMargin);
        } else {
          tree.children[i].style.margin = tree.children[i].style.margin.copyWith(top: newInternalMargin);
        }
      }
    }

    return tree;
  }

  /// [removeEmptyElements] recursively removes empty elements.
  ///
  /// An empty element is any [EmptyContentElement], any empty [TextContentElement],
  /// or any block-level [TextContentElement] that contains only whitespace and doesn't follow
  /// a block element or a line break.
  static StyledElement _removeEmptyElements(StyledElement tree) {
    List<StyledElement> toRemove = new List<StyledElement>();
    bool lastChildBlock = true;
    tree.children?.forEach((child) {
      if (child is EmptyContentElement) {
        toRemove.add(child);
      } else if (child is TextContentElement && (child.text.isEmpty)) {
        toRemove.add(child);
      } else if (child is TextContentElement && child.style.whiteSpace != WhiteSpace.PRE && tree.style.display == Display.BLOCK && child.text.trim().isEmpty && lastChildBlock) {
        toRemove.add(child);
      } else {
        _removeEmptyElements(child);
      }

      // This is used above to check if the previous element is a block element or a line break.
      lastChildBlock = (child.style.display == Display.BLOCK || child.style.display == Display.LIST_ITEM || (child is TextContentElement && child.text == '\n'));
    });
    tree.children?.removeWhere((element) => toRemove.contains(element));

    return tree;
  }

  /// [_processFontSize] changes percent-based font sizes (negative numbers in this implementation)
  /// to pixel-based font sizes.
  static StyledElement _processFontSize(StyledElement tree) {
    double parentFontSize = tree.style?.fontSize?.size ?? FontSize.medium.size;

    tree.children?.forEach((child) {
      if ((child.style.fontSize?.size ?? parentFontSize) < 0) {
        child.style.fontSize = FontSize(parentFontSize * -child.style.fontSize.size);
      }

      _processFontSize(child);
    });
    return tree;
  }

  /// [_processTextTransorm] applies text-transform css attributes
  static StyledElement _processTextTransform(StyledElement tree) {
    if (tree is TextContentElement) {
      switch (tree.style.textTransform) {
        case TextTransform.capitalize:
          tree.text = tree.text.capitalize();
          break;
        case TextTransform.uppercase:
          tree.text = tree.text.toUpperCase();
          break;
        case TextTransform.lowercase:
          tree.text = tree.text.toLowerCase();
          break;
        case TextTransform.none:
          break;
      }
    } else {
      tree.children?.forEach(_processTextTransform);
    }

    return tree;
  }
}

class _HtmlParserState extends State<HtmlParser> {
  static final _renderQueue = List<Completer>();

  final GlobalKey _htmlGlobalKey = GlobalKey();
  final GlobalKey _animatedSwitcherKey = GlobalKey();

  Completer _completer;
  bool _isOffstage = true;
  ParseResult _parseResult;

  ThemeData _themeData;
  StyledElement _cleanedTree;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;

    // If we're still waiting to run, just cancel and remove us from the render queue
    if (_completer?.isCompleted == false) {
      _completer.completeError(Exception('disposed'));
      _renderQueue.remove(_completer);
    }

    super.dispose();
  }

//  @override
//  void didChangeDependencies() {
//    context.dependOnInheritedWidgetOfExactType();
//  }

  @override
  Widget build(BuildContext context) {
    final themeData = Theme.of(context);
//    if (themeData != _themeData) {
//      _themeData = themeData;
////      _parseResult = null;
//      _parseTree(context);
//    }

    if (_parseResult == null) {
      try {
        _parseTree(context);
      } catch (error) {
        print(error);
      }
    }

    if (_parseResult != null && _isOffstage) {
      WidgetsBinding.instance.addPostFrameCallback(_afterLayout);
    }

    final children = <Widget>[];

    children.add(
      Visibility(
        visible: _isOffstage || _parseResult == null,
        maintainSize: true,
        maintainAnimation: true,
        maintainState: true,
        child: widget.loadingPlaceholder ?? Container(height: 1000),
      ),
    );

    if (!_isOffstage && _parseResult != null) {
      children.add(
        StyledText(
          key: _htmlGlobalKey,
          textSpan: _parseResult.inlineSpan,
          style: _parseResult.style,
//          textScaleFactor: MediaQuery.of(context).textScaleFactor,
        ),
      );
    }

    return Stack(
      children: <Widget>[
        if (_isOffstage && _parseResult != null)
          Offstage(
            offstage: true,
            child: StyledText(
              key: _htmlGlobalKey,
              textSpan: _parseResult.inlineSpan,
              style: _parseResult.style,
//              textScaleFactor: MediaQuery.of(context).textScaleFactor,
            ),
          ),
        AnimatedSwitcher(
          key: _animatedSwitcherKey,
          layoutBuilder: (currentChild, previousChildren) {
            return Stack(
              children: <Widget>[
                ...previousChildren,
                if (currentChild != null) currentChild,
              ],
              alignment: Alignment.topLeft,
            );
          },
          duration: kThemeAnimationDuration,
          child: Stack(
            alignment: Alignment.topLeft,
            fit: StackFit.loose,
            key: ValueKey(_isOffstage),
            children: children,
          ),
        ),
      ],
    );
  }

  void _afterLayout(Duration timeStamp) {
    final RenderBox renderBox = _htmlGlobalKey.currentContext.findRenderObject();
    final size = renderBox.size;

    print("html size: $size");

    widget.onContentRendered?.call(size);

    setState(() {
      _isOffstage = false;
    });
  }

  Future<void> _parseTree(BuildContext context) async {
    if (_completer != null) {
      if (_renderQueue.isNotEmpty) {
        _renderQueue.remove(_completer);
      }

      if (!_completer.isCompleted) {
        _completer.completeError(Exception('replaced'));
      }
    }

    _completer = Completer();
    _renderQueue.add(_completer);

    try {
      if (_renderQueue.length > 1) {
        print('_parseTree waiting for queue');
        await _completer.future;
      } else {
        _completer.complete();
      }
    } catch (exception) {
      print('_parseTree ${exception.toString()}');
      return null;
    }

    print('_parseTree parsing');

    InlineSpan parsedTree;

    try {
      if (_cleanedTree == null) {
        dom.Document document = await compute(HtmlParser.parseHTML, widget.htmlData);
        css.StyleSheet sheet = await compute(HtmlParser.parseCSS, widget.cssData);
        StyledElement lexedTree = await compute(HtmlParser._lexDomTree, [document, widget.customRender?.keys?.toList() ?? [], widget.blacklistedElements]);

        // TODO(Sub6Resources): this could be simplified to a single recursive descent.
        StyledElement styledTree = await compute(HtmlParser.applyCSS, [lexedTree, sheet]);
        StyledElement inlineStyledTree = await compute(HtmlParser.applyInlineStyles, styledTree);
        StyledElement customStyledTree = _applyCustomStyles(inlineStyledTree);
        StyledElement cascadedStyledTree = await compute(HtmlParser._cascadeStyles, customStyledTree);
        _cleanedTree = await compute(HtmlParser.cleanTree, cascadedStyledTree);
      }

      parsedTree = await HtmlParser.parseTree(
        RenderContext(
          buildContext: context,
          parser: widget,
          style: Style.fromTextStyle(Theme.of(context).textTheme.bodyText2),
        ),
        _cleanedTree,
      );

      print('_parseTree parsed');
    } catch (exception) {
      print(exception);
      return null;
    } finally {
      _renderQueue.remove(_completer);
      _completer = null;

      if (_renderQueue.isNotEmpty && !_renderQueue[0].isCompleted) {
        _renderQueue[0].complete();
      }
    }

    if (!_disposed) {
      setState(() {
        _parseResult = ParseResult(parsedTree, _cleanedTree.style);
      });
    }
  }

  /// [applyCustomStyles] applies the [Style] objects passed into the [Html]
  /// widget onto the [StyledElement] tree, no cascading of styles is done at this point.
  StyledElement _applyCustomStyles(StyledElement tree) {
    if (widget.style == null) return tree;
    widget.style.forEach((key, style) {
      if (tree.matchesSelector(key)) {
        if (tree.style == null) {
          tree.style = style;
        } else {
          tree.style = tree.style.merge(style);
        }
      }
    });
    tree.children?.forEach(_applyCustomStyles);

    return tree;
  }
}

/// The [RenderContext] is available when parsing the tree. It contains information
/// about the [BuildContext] of the `Html` widget, contains the configuration available
/// in the [HtmlParser], and contains information about the [Style] of the current
/// tree root.
class RenderContext {
  final BuildContext buildContext;
  final HtmlParser parser;
  final Style style;
  final double textScaleMultiplier;

  RenderContext({
    this.buildContext,
    this.parser,
    this.style,
    this.textScaleMultiplier,
  });
}

/// A [ContainerSpan] is a widget with an [InlineSpan] child or children.
///
/// A [ContainerSpan] can have a border, background color, height, width, padding, and margin
/// and can represent either an INLINE or BLOCK-level element.
class ContainerSpan extends StatelessWidget {
  final Widget child;
  final List<InlineSpan> children;
  final Style style;
  final RenderContext newContext;
  final bool shrinkWrap;

  ContainerSpan({
    this.child,
    this.children,
    this.style,
    this.newContext,
    this.shrinkWrap = false,
  });

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) => Container(
        decoration: BoxDecoration(
          border: style?.border,
          color: style?.backgroundColor,
        ),
        height: style?.height,
        width: style?.width,
        padding: style?.padding,
        margin: style?.margin,
        alignment: shrinkWrap ? null : style?.alignment,
        child: child ??
            StyledText(
              style: newContext.style,
              textSpan: TextSpan(
                style: newContext.style.generateTextStyle(context),
                children: children,
              ),
            ),
      ),
    );
  }
}

class StyledText extends StatelessWidget {
  const StyledText({Key key, this.textSpan, this.style, this.textScaleFactor = 1.0}) : super(key: key);

  final InlineSpan textSpan;
  final Style style;
  final double textScaleFactor;

  @override
  Widget build(BuildContext context) {
    // WidgetSpan is broken on web. See https://github.com/flutter/flutter/issues/42086
    return SizedBox(
      width: style.display == Display.BLOCK || style.display == Display.LIST_ITEM ? double.infinity : null,
      child: Text.rich(
        style.textIndent == null || style.textIndent == 0 ? textSpan : TextSpan(children: [WidgetSpan(child: SizedBox(width: max(0, style.textIndent))), textSpan]),
        style: style.generateTextStyle(context),
        textAlign: style.textAlign,
        textDirection: style.direction,
        textScaleFactor: textScaleFactor,
      ),
    );
  }
}

class ParseResult {
  final InlineSpan inlineSpan;
  final Style style;

  ParseResult(this.inlineSpan, this.style);
}
