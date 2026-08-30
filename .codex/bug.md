# Bug汇总



进聊天窗口

```
/api/chat/message/latest?sessionUnitId=cbcd06cf-2be4-473a-7270-3a09b882f73f&maxResultCount=99&minMessageId=7297401
```

加载了12条消息，是要写入数据库的

重新再进 参数minMessageId 还是 7297401 是不对的。
加载了新消息，minMessageId 应该是要比 7297401  大



