/// How much room the renderer has, which decides how much structure it shows.
///
/// Not a quality setting. The same note at widget density is not a worse version
/// of the same note at editor density; it is the most a card can carry without
/// truncating into nonsense.
enum MarkdownDensity {
  /// A widget card. Inline formatting is real; block structure is compressed.
  widget,

  /// The editor's preview pane. Everything, comfortably.
  editor,
}
