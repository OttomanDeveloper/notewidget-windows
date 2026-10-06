/// How much room the renderer has, which decides how much structure it shows.
/// Not quality: widget density is the most a card can carry without
/// truncating into nonsense.
enum MarkdownDensity {
  /// A widget card. Inline formatting is real; block structure is compressed.
  widget,

  /// The editor's preview pane. Everything, comfortably.
  editor,
}
