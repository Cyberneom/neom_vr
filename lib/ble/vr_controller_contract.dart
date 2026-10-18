import 'package:vrlizate_joystick/vrlizate_joystick.dart'
    show RemoteControllerMode;

/// The wire controls of a vrlizate_joystick phone controller.
///
/// The default layout shares navigation roles: **A** selects or performs the
/// primary action, **B** goes
/// back, **X** cycles a mode, **Y** fires the special action, **L** is the
/// utility, **R** is the game trigger (the primary game action without any
/// UI-selection semantics) and **Grip** grabs. Sticks move and look; the
/// touch pad aims the laser; shaking the phone toggles the virtual
/// controller's visibility on the visor.
/// Media experiences preserve A/B navigation and name their transport
/// shortcuts explicitly in [VrControllerContract].
/// Console layouts can display native labels over these stable wire keys:
/// NES B sends X, while its separate Home button sends the platform B key.
enum VrControllerButton {
  a('A', 'Seleccionar / acción principal'),
  b('B', 'Atrás / cancelar'),
  x('X', 'Cambiar modo'),
  y('Y', 'Acción especial'),
  l('L', 'Utilidad'),
  r('R', 'Gatillo (acción de juego)'),
  grip('GRIP', 'Agarrar');

  const VrControllerButton(this.wireKey, this.role);

  /// Key used on the wire and on the virtual controller's label atlas.
  final String wireKey;

  /// Generic role, shown when an experience gives the button no caption.
  final String role;
}

/// What each button does inside one experience.
class VrDemoControls {
  const VrDemoControls(
    this.demoId,
    this.actions, {
    this.mode = RemoteControllerMode.joystick,
  });

  final String demoId;
  final Map<VrControllerButton, String> actions;

  /// The host selects the layout when opening this experience. Home restores
  /// the navigation layout; each new console can declare its own profile here.
  final RemoteControllerMode mode;

  /// Caption for [button], or its generic role when the experience binds
  /// nothing to it.
  String label(VrControllerButton button) => actions[button] ?? button.role;

  /// Whether the experience gives [button] a specific meaning.
  bool binds(VrControllerButton button) => actions.containsKey(button);

  /// Wire/atlas form: `{'A': 'Disparar', ...}` for bound buttons only.
  Map<String, String> get wireLabels => {
    for (final entry in actions.entries) entry.key.wireKey: entry.value,
  };
}

/// One table every surface reads: the phone controller captions its keys,
/// the virtual controller in the visor draws the same words under each
/// button, the HUD can list them, and tests assert that a game binds what
/// it claims. Adding a button behaviour to a demo means adding a row here —
/// and the contract test fails until both agree.
abstract final class VrControllerContract {
  /// Experiences that must bind every button (they are games with room for
  /// all seven). Utilities and tech demos bind what they truly use.
  static const fullyBoundIds = {
    'doom_vr',
    'nes_vr',
    'open_source_flutterflip',
    'legend_of_selma',
    'tower_defense',
    'dungeon_architect',
    'crystal_mines',
    'fleet_admiral',
    'gravity_zero',
    'ecosystem',
    'treasure_hunt',
  };

  /// Longest caption that fits under a virtual-controller key.
  static const maxLabelLength = 14;

  static VrDemoControls forDemo(String demoId) =>
      _table[demoId] ?? VrDemoControls(demoId, const {});

  static const Map<String, VrDemoControls> _table = {
    // ── Retained games ──────────────────────────────────────────────
    'open_source_flutterflip': VrDemoControls('open_source_flutterflip', {
      VrControllerButton.a: 'Seleccionar',
      VrControllerButton.b: 'Guardar/Home',
      VrControllerButton.x: 'Pista',
      VrControllerButton.y: 'Pausa/seguir',
      VrControllerButton.l: 'Reiniciar',
      VrControllerButton.r: 'Seleccionar',
      VrControllerButton.grip: 'Pausa/seguir',
    }, mode: RemoteControllerMode.nes),
    'sunny_gardens': VrDemoControls('sunny_gardens', {
      VrControllerButton.a: 'Saltar',
      VrControllerButton.b: 'Guardar/Home',
      VrControllerButton.y: 'Pausa/seguir',
      VrControllerButton.l: 'Acercar',
      VrControllerButton.r: 'Saltar',
      VrControllerButton.grip: 'Pausa/seguir',
    }),
    'neon_bastion': VrDemoControls('neon_bastion', {
      VrControllerButton.a: 'Saltar',
      VrControllerButton.b: 'Guardar/Home',
      VrControllerButton.x: 'Disparar',
      VrControllerButton.y: 'Pausa/seguir',
      VrControllerButton.l: 'Acercar',
      VrControllerButton.r: 'Saltar',
      VrControllerButton.grip: 'Pausa/seguir',
    }),
    'nes_vr': VrDemoControls('nes_vr', {
      VrControllerButton.a: 'NES A',
      VrControllerButton.b: 'Guardar/Home',
      VrControllerButton.x: 'NES B',
      VrControllerButton.y: 'Inicio/pausa',
      VrControllerButton.l: 'Select',
      VrControllerButton.r: 'NES A',
      VrControllerButton.grip: 'Inicio/pausa',
    }, mode: RemoteControllerMode.nes),
    'doom_vr': VrDemoControls('doom_vr', {
      VrControllerButton.a: 'Disparar',
      VrControllerButton.b: 'Home',
      VrControllerButton.x: 'Cambiar arma',
      VrControllerButton.y: 'Usar puerta',
      VrControllerButton.l: 'Correr',
      VrControllerButton.r: 'Disparar',
      VrControllerButton.grip: 'Usar puerta',
    }),
    'legend_of_selma': VrDemoControls('legend_of_selma', {
      VrControllerButton.a: 'Espada',
      VrControllerButton.b: 'Home',
      VrControllerButton.x: 'Farol',
      VrControllerButton.y: 'Ciclo del día',
      VrControllerButton.l: 'Antorchas',
      VrControllerButton.r: 'Espada',
      VrControllerButton.grip: 'Magnesis',
    }),
    'tower_defense': VrDemoControls('tower_defense', {
      VrControllerButton.a: 'Colocar torre',
      VrControllerButton.b: 'Salir',
      VrControllerButton.x: 'Tipo de torre',
      VrControllerButton.y: 'Ataque aéreo',
      VrControllerButton.l: 'Cámara lenta',
      VrControllerButton.r: 'Colocar torre',
      VrControllerButton.grip: 'Vender',
    }),
    'dungeon_architect': VrDemoControls('dungeon_architect', {
      VrControllerButton.a: 'Poner trampa',
      VrControllerButton.b: 'Salir',
      VrControllerButton.x: 'Tipo de trampa',
      VrControllerButton.y: 'Alarma',
      VrControllerButton.l: 'Reforzar',
      VrControllerButton.r: 'Poner trampa',
      VrControllerButton.grip: 'Desarmar',
    }),
    'crystal_mines': VrDemoControls('crystal_mines', {
      VrControllerButton.a: 'Picar',
      VrControllerButton.b: 'Salir',
      VrControllerButton.x: 'Bajar nivel',
      VrControllerButton.y: 'Radar',
      VrControllerButton.l: 'Apuntalar',
      VrControllerButton.r: 'Picar',
      VrControllerButton.grip: 'Extraer',
    }),
    'fleet_admiral': VrDemoControls('fleet_admiral', {
      VrControllerButton.a: 'Elegir / fuego',
      VrControllerButton.b: 'Salir',
      VrControllerButton.x: 'Cambiar nave',
      VrControllerButton.y: 'Andanada',
      VrControllerButton.l: 'Humo',
      VrControllerButton.r: 'Fuego',
      VrControllerButton.grip: 'Cancelar',
    }),
    'gravity_zero': VrDemoControls('gravity_zero', {
      VrControllerButton.a: 'Poner / lanzar',
      VrControllerButton.b: 'Salir',
      VrControllerButton.x: 'Tipo de campo',
      VrControllerButton.y: 'Reiniciar',
      VrControllerButton.l: 'Cámara lenta',
      VrControllerButton.r: 'Lanzar',
      VrControllerButton.grip: 'Quitar',
    }),
    'ecosystem': VrDemoControls('ecosystem', {
      VrControllerButton.a: 'Crear',
      VrControllerButton.b: 'Salir',
      VrControllerButton.x: 'Especie',
      VrControllerButton.y: 'Fertilidad',
      VrControllerButton.l: 'Día / noche',
      VrControllerButton.r: 'Crear',
      VrControllerButton.grip: 'Alimentar',
    }),
    'treasure_hunt': VrDemoControls('treasure_hunt', {
      VrControllerButton.a: 'Marcar',
      VrControllerButton.b: 'Salir',
      VrControllerButton.x: 'Nueva partida',
      VrControllerButton.y: 'Sónar',
      VrControllerButton.l: '+ Tiempo',
      VrControllerButton.r: 'Marcar',
      VrControllerButton.grip: 'Telequinesis',
    }),
    // ── Retained utilities ──────────────────────────────────────────
    'spatial_ui': VrDemoControls('spatial_ui', {
      VrControllerButton.a: 'Pulsar',
      VrControllerButton.b: 'Salir',
    }),
    'hand_tracking': VrDemoControls('hand_tracking', {
      VrControllerButton.a: 'Tocar',
      VrControllerButton.b: 'Salir',
      VrControllerButton.x: 'Visión RF',
    }),
    'wifi_sensing': VrDemoControls('wifi_sensing', {
      VrControllerButton.a: 'Tocar',
      VrControllerButton.b: 'Salir',
      VrControllerButton.x: 'Visión RF',
    }),
    // ── Native scenes ───────────────────────────────────────────────
    'riviera_rush': VrDemoControls('riviera_rush', {
      VrControllerButton.a: 'Pausa/seguir',
      VrControllerButton.b: 'Home',
      VrControllerButton.x: 'Reiniciar',
      VrControllerButton.l: 'Vista −',
      VrControllerButton.r: 'Vista +',
    }, mode: RemoteControllerMode.driving),
    'cosmic_chess': VrDemoControls('cosmic_chess', {
      VrControllerButton.a: 'Elegir casilla',
      VrControllerButton.b: 'Salir',
      VrControllerButton.x: 'Girar tablero',
      VrControllerButton.y: 'Pista',
      VrControllerButton.l: 'Centrar vista',
      VrControllerButton.grip: 'Coger pieza',
    }),
    'medieval_siege': VrDemoControls('medieval_siege', {
      VrControllerButton.a: 'Disparar',
      VrControllerButton.b: 'Salir',
      VrControllerButton.x: 'Modo de tiro',
      VrControllerButton.y: 'Salva',
      VrControllerButton.l: 'Noche',
    }),
    'vr_kanban': VrDemoControls('vr_kanban', {
      VrControllerButton.a: 'Elegir tarjeta',
      VrControllerButton.b: 'Salir',
      VrControllerButton.x: 'Columna',
      VrControllerButton.y: 'Escribir',
      VrControllerButton.l: 'Cancelar',
      VrControllerButton.grip: 'Soltar tarjeta',
    }),
    'openworld': VrDemoControls('openworld', {
      VrControllerButton.a: 'Elegir',
      VrControllerButton.b: 'Home',
      VrControllerButton.x: 'Otro bioma',
      VrControllerButton.y: 'Noche',
      VrControllerButton.l: 'Clima',
    }),
    'vr_gallery': VrDemoControls('vr_gallery', {
      VrControllerButton.a: 'Inspeccionar',
      VrControllerButton.b: 'Salir',
      VrControllerButton.x: 'Siguiente obra',
      VrControllerButton.y: 'Soltar obra',
      VrControllerButton.l: 'Luces',
    }),
    'orbital_command': VrDemoControls('orbital_command', {
      VrControllerButton.a: 'Elegir',
      VrControllerButton.b: 'Salir',
    }),
    'portal_maze': VrDemoControls('portal_maze', {
      VrControllerButton.a: 'Elegir',
      VrControllerButton.b: 'Salir',
    }),
    'vr_cinema': VrDemoControls('vr_cinema', {
      VrControllerButton.a: 'Seleccionar',
      VrControllerButton.b: 'Atrás',
      VrControllerButton.x: 'Pausa/seguir',
      VrControllerButton.y: 'Pantalla cine',
      VrControllerButton.l: '−10 s',
      VrControllerButton.r: '+10 s',
      // Grip is emitted automatically after holding the laser pad for 280 ms.
      // Binding it to mute would change audio while simply aiming. Sound is
      // an explicit world-panel action, selected with A; Grip stays unbound.
    }),
    'vr_dashboard': VrDemoControls('vr_dashboard', {
      VrControllerButton.a: 'Elegir',
      VrControllerButton.b: 'Salir',
    }),
    'vr_notes': VrDemoControls('vr_notes', {
      VrControllerButton.a: 'Elegir',
      VrControllerButton.b: 'Salir',
    }),
    'wordsphere': VrDemoControls('wordsphere', {
      VrControllerButton.a: 'Confirmar',
      VrControllerButton.b: 'Cancelar/salir',
      VrControllerButton.x: 'Trazo / listo',
    }),
    'wordsphere_vr': VrDemoControls('wordsphere_vr', {
      VrControllerButton.a: 'Confirmar',
      VrControllerButton.b: 'Cancelar/salir',
      VrControllerButton.x: 'Trazo / listo',
    }),
    'holographic_hands': VrDemoControls('holographic_hands', {
      VrControllerButton.a: 'Elegir',
      VrControllerButton.b: 'Salir',
    }),
    'stereo_scene': VrDemoControls('stereo_scene', {
      VrControllerButton.a: 'Elegir',
      VrControllerButton.b: 'Salir',
    }),
    'flutter_scene_room': VrDemoControls('flutter_scene_room', {
      VrControllerButton.a: 'Restablecer',
      VrControllerButton.b: 'Salir',
    }),
    'thermion_room': VrDemoControls('thermion_room', {
      VrControllerButton.a: 'Restablecer',
      VrControllerButton.b: 'Salir',
    }),
    'hello_vr': VrDemoControls('hello_vr', {
      VrControllerButton.a: 'Elegir',
      VrControllerButton.b: 'Salir',
    }),
    'viewer_calibration': VrDemoControls('viewer_calibration', {
      VrControllerButton.a: 'Elegir',
      VrControllerButton.b: 'Salir',
    }),
  };

  /// Ids with an explicit row; the contract test checks it against the
  /// registry so a new demo cannot ship without declaring its controls.
  static Iterable<String> get declaredDemoIds => _table.keys;
}
