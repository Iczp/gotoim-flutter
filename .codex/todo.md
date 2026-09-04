修改群名称
参考
F:\Dev\GotoIM\gotoim-mobile\gotoim-uniapp-ts\src\pages\im\sessions\group-name.vue



账号设置 

参考
F:\Dev\GotoIM\gotoim-mobile\gotoim-uniapp-ts\src\pages\account\profile.vue



## 消息结构

- 复选框（编辑模式下才显示）
- 消息（占满）
  - 头像（有参数是否显示）
  - 消息内容（占满）
    - 各种消息（自个约束）
      - 文本
        - 气泡
        - 上传状态/下载状态
      - 语音
        - 气泡
        - 上传状态/未播放红点
      - 图片
      - 视频
      - ...
    - 引用消息

气泡

消息最小高度是44，  气泡尾巴是 22 , 单行看起来居中，两行也是要在22， 

剪裁掉的上圆型，太大，凹进去，不能超过相切的位置

- 消息内容
  - 发送人名称(各自加padding: 12)
  - 各种消息（文本、语音、图片、视频、文件等）- 不加padding,  气泡尾巴宽度12
  - 引用消息(各自加padding: 12)
  - 其他内容，可扩展(各自加padding: 12)

这个间隔 12  统一设置 ，气泡背景透明 0.75

附件缓存保存要分类，按消息日期保存，局域网文件管理站，要能管理到这个附件

聊天窗口 lib\features\chat\presentation\chat_page.dart
头像菜单 和 消息菜单 按住 时，在华为手机上没有 振动反馈

### set-background-image 404

http://10.0.5.20:8044/api/chat/session-unit-setting/set-background-image/f8ff9588-4b6b-0c3e-f6c5-3a0aab0196c9?backgroundImage=%2Fdata%2Fuser%2F0%2Fcom.example.gotoim_flutter%2Fcache%2Ff17edb35-f478-4277-a38b-74639d311b3c%2FIMG_20260901_201951.jpg



