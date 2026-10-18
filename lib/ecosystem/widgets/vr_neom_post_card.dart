import 'package:flutter/material.dart';
import 'package:neom_commons/ui/widgets/post_tile.dart';
import 'package:neom_commons/ui/widgets/profile_stat_item.dart';
import 'package:neom_core/domain/model/post.dart';
import 'package:neom_core/utils/enums/post_type.dart';

/// A spatial presentation of an already authorized NEOM post.
///
/// The host owns the post's account scope and must remove this presentation
/// when that scope expires. The surface never starts playback or opens routes;
/// selection and paging stay with the room's shared joystick actions.
class VrNeomPostCard extends StatelessWidget {
  const VrNeomPostCard({super.key, required this.post});

  static const logicalSize = Size(720, 360);

  final Post post;

  bool get _hasImage =>
      (post.type == PostType.image && post.mediaUrl.isNotEmpty) ||
      (post.type == PostType.video && post.thumbnailUrl.isNotEmpty);

  @override
  Widget build(BuildContext context) => ExcludeFocus(
    child: IgnorePointer(
      child: Material(
        color: const Color(0xff101b29),
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_hasImage) ...[
                SizedBox(
                  width: 220,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: PostTile(post, null, showStats: false),
                  ),
                ),
                const SizedBox(width: 24),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.account_circle_outlined,
                          color: Color(0xff83ddd4),
                          size: 32,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            post.profileName.isEmpty
                                ? 'Comunidad'
                                : post.profileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 25,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (post.isPrivate)
                          const Icon(Icons.lock_outline, color: Colors.white70),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Expanded(
                      child: Text(
                        post.caption,
                        maxLines: _hasImage ? 6 : 7,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          height: 1.3,
                        ),
                      ),
                    ),
                    if (post.id.startsWith('pending_'))
                      const Text(
                        'Pendiente de envío',
                        style: TextStyle(
                          color: Color(0xffffd08b),
                          fontSize: 17,
                        ),
                      ),
                    Row(
                      children: [
                        ProfileStatItem(
                          label: 'Me gusta',
                          value: '${post.likedProfiles.length}',
                          icon: Icons.favorite_border,
                        ),
                        const SizedBox(width: 18),
                        ProfileStatItem(
                          label: 'Comentarios',
                          value: '${post.commentIds.length}',
                          icon: Icons.chat_bubble_outline,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
