# Bug汇总



进聊天窗口

```
/api/chat/message/latest?sessionUnitId=cbcd06cf-2be4-473a-7270-3a09b882f73f&maxResultCount=99&minMessageId=7297401
```

加载了12条消息，是要写入数据库的 -- 请检查

重新再进 参数minMessageId 还是 7297401 是不对的。
加载了新消息，minMessageId 应该是要比 7297401  大



这是两个进入相关会话  /api/chat/message/latest 都反回了30条，理论上第一次返回30条，进入数据库，第二次应该是要 更新 获取本地的最大MessageId 传到  接口的 minMessageId 

MethodAddressStatusTypeDurationSizeTimestampSOCKET10.0.5.20:8044Closedtcp4 s58.1 kB13:53:40.200SOCKET10.0.5.20:8044Closedtcp3 s2.6 kB13:53:40.375GEThttp://10.0.5.20:8044/api/chat/session-unit-cache/friend/221a1d41-2c74-c701-b407-3a0b0cf4331e200json111 ms-13:53:40.636GEThttp://10.0.5.20:8044/api/chat/message/latest?sessionUnitId=221a1d41-2c74-c701-b407-3a0b0cf4331e&maxResultCount=99&minMessageId=7297037200json80 ms-13:53:40.751POSThttp://10.0.5.20:8044/api/chat/session-unit-setting/set-read?sessionUnitId=221a1d41-2c74-c701-b407-3a0b0cf4331e&messageId=7297037200json184 ms-13:53:40.806POSThttp://10.0.5.20:8044/api/chat/session-unit-setting/set-read?sessionUnitId=221a1d41-2c74-c701-b407-3a0b0cf4331e&messageId=7297320200json120 ms-13:53:41.106SOCKET10.0.5.20:8044Closedtcp3 s3.5 kB13:54:07.931SOCKET10.0.5.20:8044Closedtcp4 s57.2 kB13:54:07.964GEThttp://10.0.5.20:8044/api/chat/session-unit-cache/friend/221a1d41-2c74-c701-b407-3a0b0cf4331e200json148 ms-13:54:08.284GEThttp://10.0.5.20:8044/api/chat/message/latest?sessionUnitId=221a1d41-2c74-c701-b407-3a0b0cf4331e&maxResultCount=99&minMessageId=7297037200json98 ms-13:54:08.398POSThttp://10.0.5.20:8044/api/chat/session-unit-setting/set-read?sessionUnitId=221a1d41-2c74-c701-b407-3a0b0cf4331e&messageId=7297037200json130 ms-13:54:08.513POSThttp://10.0.5.20:8044/api/chat/session-unit-setting/set-read?sessionUnitId=221a1d41-2c74-c701-b407-3a0b0cf4331e&messageId=7297320200json164 ms-13:54:08.811

### 进聊天窗口\

friend detai   中没有lastMessage,  因此，要先读取本地的friend  lastMessage, 再合并。   





