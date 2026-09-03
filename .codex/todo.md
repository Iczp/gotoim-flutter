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
  - 发送人名称
  - 各种消息（文本、语音、图片、视频、文件等）
  - 引用消息
  - 其他内容