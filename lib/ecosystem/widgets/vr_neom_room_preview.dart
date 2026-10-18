import 'package:flutter/material.dart';
import 'package:neom_commons/ui/widgets/profile_stat_item.dart';
import 'package:vrlizate_home/vrlizate_home.dart';

/// Public room identity; labels describe the space, never invented user data.
class VrNeomRoomPreview extends StatelessWidget {
  const VrNeomRoomPreview({
    super.key,
    required this.room,
    required this.status,
  });

  static const logicalSize = Size(720, 300);

  final VrHomeEcosystemRoom room;
  final String status;

  @override
  Widget build(BuildContext context) {
    final accent = Color(room.accent);
    final (icon, headline, details) = switch (room.purpose) {
      VrHomeRoomPurpose.avatar => (
        Icons.accessibility_new_rounded,
        'Tu presencia dentro del mundo virtual',
        const ['Apariencia', 'Estatura virtual', 'Convivencia'],
      ),
      VrHomeRoomPurpose.profile => (
        Icons.account_circle_outlined,
        'Tu identidad tiene su propio espacio',
        const ['Perfil', 'Seguidores', 'Actividad'],
      ),
      VrHomeRoomPurpose.social => (
        Icons.forum_outlined,
        'La comunidad, a tu alrededor',
        const ['Muro', 'Imágenes', 'Publicaciones'],
      ),
      VrHomeRoomPurpose.creation => (
        Icons.view_in_ar_outlined,
        'Un taller para tus experiencias',
        const ['Ideas', 'Proyectos', '.vrlz'],
      ),
      VrHomeRoomPurpose.reading => (
        Icons.auto_stories_outlined,
        'Historias que ocupan un lugar',
        const ['Biblioteca', 'Libros', 'Audiolibros'],
      ),
      VrHomeRoomPurpose.music => (
        Icons.headphones_outlined,
        'Un espacio para escuchar',
        const ['Música', 'Artistas', 'Descubrimiento'],
      ),
      VrHomeRoomPurpose.meditation => (
        Icons.spa_outlined,
        'Haz una pausa en tu recorrido',
        const ['Calma', 'Meditación', 'Bienestar'],
      ),
      VrHomeRoomPurpose.cinema => (
        Icons.movie_outlined,
        'Una pantalla a escala de cine',
        const ['YouTube', 'Pantalla 16:9', 'Mando VR'],
      ),
      VrHomeRoomPurpose.openSourceGames => (
        Icons.sports_esports_outlined,
        'Juegos abiertos, con sus creadores',
        const ['Galería', 'Código fuente', 'Joystick'],
      ),
    };
    return ExcludeFocus(
      child: IgnorePointer(
        child: Material(
          color: Colors.transparent,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: accent.withValues(alpha: .5)),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(const Color(0xff101a2b), accent, .16)!,
                  const Color(0xff10141d),
                ],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
              child: Row(
                children: [
                  Container(
                    width: 132,
                    height: 190,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: .09),
                      borderRadius: BorderRadius.circular(36),
                      border: Border.all(color: accent.withValues(alpha: .3)),
                    ),
                    child: Icon(icon, size: 82, color: accent),
                  ),
                  const SizedBox(width: 30),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          room.title.toUpperCase(),
                          style: TextStyle(
                            color: accent,
                            fontSize: 17,
                            letterSpacing: 2.1,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          headline,
                          maxLines: 2,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            height: 1.1,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          status,
                          maxLines: 2,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 10),
                        MediaQuery.withClampedTextScaling(
                          minScaleFactor: 1.5,
                          maxScaleFactor: 1.5,
                          child: Row(
                            children: [
                              for (final detail in details)
                                Expanded(
                                  child: ProfileStatItem(
                                    label: detail,
                                    value: '•',
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
