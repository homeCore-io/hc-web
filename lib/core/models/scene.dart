class SceneModel {
  final String id;
  final String name;
  final Map<String, dynamic> states;

  SceneModel({required this.id, required this.name, required this.states});

  factory SceneModel.fromJson(Map<String, dynamic> json) => SceneModel(
        id: json['id'] as String,
        name: json['name'] as String? ?? json['id'] as String,
        states: Map<String, dynamic>.from(json['states'] as Map? ?? {}),
      );
}
