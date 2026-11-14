/// Wire contracts for KIITPulse.
///
/// These types mirror `contracts/proto/kiitpulse/v1/kiitpulse.proto` field for
/// field. They are hand-written Dart today; the moment `buf` is wired up, the
/// generated classes are adapted into these and every feature keeps compiling
/// because features only ever depend on this library.
library kiit_contracts;

export 'src/campus_zone.dart';
export 'src/topic_pulse.dart';
export 'src/chat_frame.dart';
export 'src/velocity.dart';
export 'src/voice_stage.dart';
export 'src/badge.dart';
