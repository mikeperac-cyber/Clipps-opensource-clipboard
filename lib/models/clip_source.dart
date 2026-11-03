/// Where a clip was copied from. Display only; never used for logic.
class ClipSource {
  const ClipSource({this.app, this.title});

  final String? app;
  final String? title;

  @override
  bool operator ==(Object other) =>
      other is ClipSource && other.app == app && other.title == title;

  @override
  int get hashCode => Object.hash(app, title);
}
