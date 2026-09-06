import 'package:flutter/material.dart';
import '../../../app/theme.dart';

class EmojiPickerWidget extends StatefulWidget {
  final ValueChanged<String> onEmojiSelected;
  final VoidCallback onBackspace;

  const EmojiPickerWidget({
    super.key,
    required this.onEmojiSelected,
    required this.onBackspace,
  });

  @override
  State<EmojiPickerWidget> createState() => _EmojiPickerWidgetState();
}

class _EmojiPickerWidgetState extends State<EmojiPickerWidget>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const List<String> _smileys = [
    '😀', '😃', '😄', '😁', '😆', '😅', '😂', '🤣', '🥲', '🥹',
    '😊', '😇', '🙂', '🙃', '😉', '😌', '😍', '🥰', '😘', '😗',
    '😙', '😚', '😋', '😛', '😝', '😜', '🤪', '🤨', '🧐', '🤓',
    '😎', '🥸', '🤩', '🥳', '😏', '😒', '😞', '😔', '😟', '😕',
    '🙁', '☹️', '😣', '😖', '😫', '😩', '🥺', '😢', '😭', '😮‍💨',
    '😤', '😠', '😡', '🤬', '🤯', '😳', '🥵', '🥶', '😱', '😨',
    '😰', '😥', '😓', '🫣', '🤫', '🫡', '🤥', '😶', '😐', '😑',
    '😬', '🫨', '🫠', '🙄', '😯', '😦', '😧', '😮', '😲', '🥱',
    '😴', '🤤', '😪', '😵', '😵‍💫', '🤐', '🥴', '🤢', '🤮', '🤧',
    '😷', '🤒', '🤕', '🤑', '🤠', '😈', '👿', '👹', '👺', '🤡',
    '💩', '👻', '💀', '☠️', '👽', '👾', '🤖', '🎃', '😺', '😸',
    '😹', '😻', '😼', '😽', '🙀', '😿', '😾', '🙈', '🙉', '🙊'
  ];

  static const List<String> _people = [
    '👍', '👎', '👏', '🙌', '👐', '🤲', '🤝', '👊', '✊', '🤛',
    '🤜', '🤞', '✌️', '🫰', '🤟', '🤘', '👌', '🤌', '🤏', '👈',
    '👉', '👆', '👇', '☝️', '✋', '🤚', '🖐️', '🖖', '👋', '🤙',
    '🫱', '🫲', '🫵', '🖕', '✍️', '🙏', '💅', '🤳', '💪', '🦾',
    '🦿', '🦵', '🦶', '👂', '🦻', '👃', '🧠', '🫀', '🫁', '🦷',
    '🦴', '👀', '👁️', '👅', '👄', '🫦', '👶', '🧒', '👦', '👧',
    '🧑', '👱', '👨', '🧔', '👩', '🧓', '👴', '👵', '🙍', '🙎',
    '🙅', '🙆', '💁', '🙋', '🧏', '🙇', '🤦', '🤷', '🧑‍⚕️', '🧑‍🎓',
    '🧑‍🏫', '🧑‍⚖️', '🧑‍🌾', '🧑‍🍳', '🧑‍🔧', '🧑‍🏭', '🧑‍💼', '🧑‍🔬', '🧑‍💻', '🧑‍🎤',
    '🧑‍🎨', '🧑‍✈️', '🧑‍🚀', '🧑‍🚒', '👮', '🕵️', '💂', '👷', '🤴', '👸',
    '👳', '👲', '🧕', '🤵', '👰', '🤰', '🤱', '👼', '🎅', '🤶',
    '🦸', '🦹', '🧙', '🧚', '🧛', '🧜', '🧝', '🧞', '🧟', '💆',
    '💇', '🚶', '🧍', '🧎', '🏃', '💃', '🕺', '🕴️', '🧖', '🧗',
    '🧘', '🛀', '🛌', '👭', '👫', '👬', '💏', '💑', '👪'
  ];

  static const List<String> _hearts = [
    '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍', '🤎', '💔',
    '❣️', '💕', '💞', '💓', '💗', '💖', '💘', '💝', '💟', '❤️‍🔥',
    '❤️‍🩹', '💋', '💌', '💍', '💎', '💐', '🌹', '🥀', '🌺', '🌸',
    '🌼', '🌻', '🌷', '🪷', '💫', '⭐', '🌟', '✨', '⚡', '💥',
    '🔥', '🫀', '💯', '💢', '💨', '💤', '🎉', '🎊', '🎀', '🎁',
    '🎈', '🪅', '🪄', '🔮', '🧿', '🪬', '👑', '🏆', '🥇', '🥈',
    '🥉', '🎖️', '🏅', '🎗️', '🎫', '🎟️', '🏷️', '📢', '📣', '🔔',
    '🔕', '🎵', '🎶', '💬', '👁️‍🗨️', '🗨️', '🗯️', '💭', '♨️', '🛑',
    '⛔', '📛', '🚫', '⚠️', '🚸', '⚜️', '〽️', '🚳', '🚭', '🚯',
    '🚱', '🚷', '📵', '🔞', '☢️', '☣️', '⬆️', '↗️', '➡️', '↘️',
    '⬇️', '↙️', '⬅️', '↖️', '↕️', '↔️', '↩️', '↪️', '⤴️', '⤵️',
    '🔄', '🔀', '🔁', '🔂', '▶️', '⏩', '⏭️', '⏯️', '◀️', '⏪',
    '⏮️', '🔼', '⏫', '🔽', '⏬', '⏸️', '⏹️', '⏺️', '⏏️', '🎦',
    '📳', '📴', '♀️', '♂️', '⚧️', '✖️', '➕', '➖', '➗', '♾️',
    '‼️', '⁉️', '❓', '❔', '❕', '❗️', '〰️', '💱', '💲', '💹',
    '❇️', '✳️', '❎', '✅', '✔️', '☑️', '🔘', '🔴', '🟠', '🟡',
    '🟢', '🔵', '🟣', '⚫', '⚪', '🟤', '🔺', '🔻', '🔹', '🔷',
    '🔸', '🔶', '🔳', '🔲', '▫️', '▪️', '◽', '◾', '◻️', '◼️',
    '⬜', '⬛'
  ];

  static const List<String> _animals = [
    '🐶', '🐱', '🐭', '🐹', '🐰', '🦊', '🐻', '🐼', '🐻‍❄️', '🐨',
    '🐯', '🦁', '🐮', '🐷', '🐽', '🐸', '🐵', '🐒', '🐔', '🐧',
    '🐦', '🐤', '🐣', '🐥', '🦆', '🦅', '🦉', '🦇', '🐺', '🐗',
    '🐴', '🦄', '🐝', '🪱', '🐛', '🦋', '🐌', '🐞', '🐜', '🪰',
    '🪲', '🪳', '🦟', '🦗', '🕷️', '🕸️', '🦂', '🐢', '🐍', '🦎',
    '🦖', '🦕', '🐙', '🦑', '🦐', '🦞', '🦀', '🐡', '🐠', '🐟',
    '🐬', '🐳', '🐋', '🦈', '🐊', '🐅', '🐆', '🦓', '🦍', '🦧',
    '🦣', '🐘', '🦛', '🦏', '🐪', '🐫', '🦒', '🦘', '🦬', '🐃',
    '🐂', '🐄', '🐎', '🐖', '🐏', '🐑', '🦙', '🐐', '🦌', '🐕',
    '🐩', '🦮', '🐕‍🦺', '🐈', '🐈‍⬛', '🐓', '🦃', '🦚', '🦜', '🦢',
    '🦩', '🕊️', '🐇', '🦝', '🦨', '🦡', '🦫', '🦦', '🦥', '🐁',
    '🐀', '🐿️', '🦔', '🐾', '🌲', '🌳', '🌴', '🪵', '🌿', '☘️',
    '🍀', '🍁', '🍂', '🍃', '🍄', '🪨', '🌾', '💐', '🌷', '🌹',
    '🥀', '🌺', '🌸', '🌼', '🌻', '🌞', '🌝', '🌛', '🌜', '🌚',
    '🌕', '🌖', '🌗', '🌘', '🌑', '🌒', '🌓', '🌔', '🌙', '🌎',
    '🌍', '🌏', '🪐', '💫', '⭐️', '🌟', '✨', '⚡️', '☄️', '💥',
    '🔥', '🌪️', '🌈', '☀️', '🌤️', '⛅️', '🌥️', '☁️', '🌦️', '🌧️',
    '⛈️', '🌩️', '🌨️', '❄️', '☃️', '⛄️', '🌬️', '💨', '💧', '💦',
    '🫧', '☔️', '☂️', '🌊', '🌫️'
  ];

  static const List<String> _food = [
    '🍏', '🍎', '🍐', '🍊', '🍋', '🍌', '🍉', '🍇', '🍓', '🫐',
    '🍈', '🍒', '🍑', '🥭', '🍍', '🥥', '🥝', '🍅', '🍆', '🥑',
    '🥦', '🥬', '🥒', '🌶️', '🫑', '🌽', '🥕', '🫒', '🧄', '🧅',
    '🥔', '🍠', '🥐', '🥯', '🍞', '🥖', '🥨', '🧀', '🥚', '🍳',
    '🧈', '🥞', '🧇', '🥓', '🥩', '🍗', '🍖', '🦴', '🌭', '🍔',
    '🍟', '🍕', '🫓', '🥪', '🥙', '🧆', '🌮', '🌯', '🫔', '🥗',
    '🥘', '🫕', '🥫', '🍝', '🍜', '🍲', '🍛', '🍣', '🍱', '🥟',
    '🦪', '🍤', '🍙', '🍚', '🍘', '🍥', '🥠', '🥮', '🍢', '🍡',
    '🍧', '🍨', '🍦', '🥧', '🧁', '🍰', '🎂', '🍮', '🍭', '🍬',
    '🍫', '🍿', '🍩', '🍪', '🌰', '🥜', '🍯', '🥛', '🍼', '☕️',
    '🍵', '🧃', '🥤', '🧋', '🍶', '🍺', '🍻', '🥂', '🍷', '🥃',
    '🍸', '🍹', '🍾', '🧊', '🥄', '🍴', '🍽️', '🥣', '🥡', '🥢',
    '🧂'
  ];

  static const List<String> _activities = [
    '⚽️', '🏀', '🏈', '⚾️', '🥎', '🎾', '🏐', '🏉', '🥏', '🎱',
    '🪀', '🏓', '🏸', '🏒', '🏑', '🥍', '🏏', '🪃', '🥅', '⛳️',
    '🪁', '🏹', '🎣', '🤿', '🥊', '🥋', '🎽', '🛹', '🛼', '🛷',
    '⛸️', '🥌', '🎿', '⛷️', '🏂', '🪂', '🏋️', '🏋️‍♂️', '🏋️‍♀️', '🤼',
    '🤼‍♂️', '🤼‍♀️', '🤸', '🤸‍♂️', '🤸‍♀️', '⛹️', '⛹️‍♂️', '⛹️‍♀️', '🤺', '🤾',
    '🤾‍♂️', '🤾‍♀️', '🏌️', '🏌️‍♂️', '🏌️‍♀️', '🏇', '🧘', '🧘‍♂️', '🧘‍♀️', '🏄',
    '🏄‍♂️', '🏄‍♀️', '🏊', '🏊‍♂️', '🏊‍♀️', '🤽', '🤽‍♂️', '🤽‍♀️', '🚣', '🚣‍♂️',
    '🚣‍♀️', '🧗', '🧗‍♂️', '🧗‍♀️', '🚵', '🚵‍♂️', '🚵‍♀️', '🚴', '🚴‍♂️', '🚴‍♀️',
    '🏆', '🥇', '🥈', '🥉', '🏅', '🎖️', '🏵️', '🎗️', '🎫', '🎟️',
    '🎪', '🤹', '🤹‍♂️', '🤹‍♀️', '🎭', '🩰', '🎨', '🎬', '🎤', '🎧',
    '🎼', '🎹', '🥁', '🪘', '🎷', '🎺', '🎸', '🪕', '🎻', '🎲',
    '♟️', '🎯', '🎳', '🎮', '🎰', '🧩'
  ];

  static const List<String> _travel = [
    '🚗', '🚕', '🚙', '🚌', '🚎', '🏎️', '🚓', '🚑', '🚒', '🚐',
    '🛻', '🚚', '🚛', '🚜', '🛴', '🚲', '🛵', '🏍️', '🛺', '🚨',
    '🚔', '🚍', '🚘', '🚖', '🚡', '🚠', '🚟', '🚃', '🚋', '🚞',
    '🚝', '🚄', '🚅', '🚈', '🚂', '🚆', '🚇', '🚊', '🚉', '✈️',
    '🛫', '🛬', '🛩️', '💺', '🛰️', '🚀', '🛸', '🚁', '🛶', '⛵️',
    '🚤', '🛥️', '🛳️', '⛴️', '🚢', '⚓️', '🛟', '⛽️', '🚧', '🚦',
    '🚥', '🗺️', '🗿', '🗽', '🗼', '🏰', '🏯', '🏟️', '🎡', '🎢',
    '🎠', '⛲️', '⛱️', '🏖️', '🏝️', '🏜️', '🌋', '⛰️', '🏔️', '🗻',
    '🏕️', '⛺️', '🛖', '🏠', '🏡', '🏘️', '🏚️', '🏗️', '🏭', '🏢',
    '🏬', '🏣', '🏤', '🏥', '🏦', '🏨', '🏪', '🏫', '🏩', '💒',
    '🏛️', '⛪️', '🕌', '🛕', '🕍', '⛩️', '🕋'
  ];

  static const List<String> _objects = [
    '📱', '📲', '💻', '⌨️', '🖥️', '🖨️', '🖱️', '🖲️', '🕹️', '🗜️',
    '💽', '💾', '💿', '📀', '📼', '📷', '📸', '📹', '🎥', '📽️',
    '🎞️', '📞', '☎️', '📟', '📠', '📺', '📻', '🎙️', '🎚️', '🎛️',
    '⏱️', '⏲️', '⏰', '🕰️', '⌛️', '⏳', '📡', '🔋', '🪫', '🔌',
    '💡', '🔦', '🕯️', '🪔', '🧯', '🛢️', '💸', '💵', '💴', '💶',
    '💷', '🪙', '💰', '💳', '💎', '⚖️', '🪜', '🧰', '🪛', '🔧',
    '🔨', '⚒️', '🛠️', '⛏️', '🪚', '🔩', '⚙️', '🪤', '🧱', '⛓️',
    '🧲', '🔫', '💣', '🧨', '🪓', '🔪', '🗡️', '⚔️', '🛡️', '🚬',
    '⚰️', '🪦', '⚱️', '🏺', '🔮', '📿', '🧿', '💈', '⚗️', '🔭',
    '🔬', '🕳️', '🩹', '🩺', '💊', '💉', '🩸', '🧬', '🦠', '🧫',
    '🧪', '🌡️', '🧹', '🪠', '🧺', '🧻', '🚽', '🚰', '🚿', '🛁',
    '🛀', '🧼', '🪥', '🪒', '🧽', '🪣', '🧴', '🔑', '🗝️', '🚪',
    '🪑', '🛋️', '🛏️', '🛌', '🧸', '🪆', '🖼️', '🪞', '🪟', '🛍️',
    '🛒', '🎁', '🎈', '🎏', '🎀', '🪄', '🪅', '🎊', '🎉', '🎎',
    '🏮', '🎐', '🧧', '✉️', '📩', '📨', '📧', '💌', '📮', '📦',
    '🏷️', '📁', '📂', '📑', '🗞️', '📰', '📓', '📕', '📗', '📘',
    '📙', '📚', '📖', '🔖', '🔗', '📎', '🖇️', '📐', '📏', '📌',
    '📍', '✂️', '🖊️', '🖋️', '✒️', '🖌️', '🖍️', '📝', '✏️', '🔍',
    '🔎', '🔒', '🔓', '🔏', '🔐'
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 8, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 290,
      decoration: const BoxDecoration(
        color: MineTheme.surfaceDark,
        border: Border(
          top: BorderSide(color: Colors.white10, width: 0.5),
        ),
      ),
      child: Column(
        children: [
          // Category Tab Bar + Backspace Button
          Container(
            height: 44,
            decoration: BoxDecoration(
              color: MineTheme.backgroundDark.withAlpha(120),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    indicatorColor: MineTheme.primaryTeal,
                    indicatorWeight: 3,
                    labelColor: MineTheme.primaryTeal,
                    unselectedLabelColor: MineTheme.textMuted,
                    dividerColor: Colors.transparent,
                    padding: EdgeInsets.zero,
                    tabs: const [
                      Tab(icon: Icon(Icons.sentiment_satisfied_alt_outlined, size: 20)),
                      Tab(icon: Icon(Icons.thumb_up_alt_outlined, size: 20)),
                      Tab(icon: Icon(Icons.favorite_border, size: 20)),
                      Tab(icon: Icon(Icons.pets_outlined, size: 20)),
                      Tab(icon: Icon(Icons.fastfood_outlined, size: 20)),
                      Tab(icon: Icon(Icons.sports_soccer_outlined, size: 20)),
                      Tab(icon: Icon(Icons.directions_car_outlined, size: 20)),
                      Tab(icon: Icon(Icons.lightbulb_outline, size: 20)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.backspace_outlined, size: 20, color: MineTheme.textMuted),
                  tooltip: 'Backspace',
                  onPressed: widget.onBackspace,
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
          // Emoji Grid Views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildEmojiGrid(_smileys),
                _buildEmojiGrid(_people),
                _buildEmojiGrid(_hearts),
                _buildEmojiGrid(_animals),
                _buildEmojiGrid(_food),
                _buildEmojiGrid(_activities),
                _buildEmojiGrid(_travel),
                _buildEmojiGrid(_objects),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmojiGrid(List<String> emojis) {
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 8,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
      ),
      itemCount: emojis.length,
      itemBuilder: (context, index) {
        final emoji = emojis[index];
        return InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => widget.onEmojiSelected(emoji),
          child: Center(
            child: Text(
              emoji,
              style: const TextStyle(fontSize: 24),
            ),
          ),
        );
      },
    );
  }
}
