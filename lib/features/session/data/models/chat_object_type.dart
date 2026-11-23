/// 后端 `ChatObjectTypeEnums` 权威聊天对象类型常量定义。
abstract final class ChatObjectTypeValues {
  static const int anonymous = 0;
  static const int personal = 1;
  static const int room = 2;
  static const int official = 3;
  static const int subscription = 4;
  static const int square = 5;
  static const int robot = 6;
  static const int shopKeeper = 7;
  static const int shopWaiter = 8;
  static const int customer = 9;
}

/// 根据后端 `objectType` 枚举值映射可读的中文对象类型名称。
String chatObjectTypeLabel(int? objectType) => switch (objectType) {
  ChatObjectTypeValues.anonymous => '匿名',
  ChatObjectTypeValues.personal => '个人',
  ChatObjectTypeValues.room => '群聊',
  ChatObjectTypeValues.official => '服务号',
  ChatObjectTypeValues.subscription => '订阅号',
  ChatObjectTypeValues.square => '广场',
  ChatObjectTypeValues.robot => '机器人',
  ChatObjectTypeValues.shopKeeper => '掌柜',
  ChatObjectTypeValues.shopWaiter => '店小二',
  ChatObjectTypeValues.customer => '客户',
  _ => '',
};
