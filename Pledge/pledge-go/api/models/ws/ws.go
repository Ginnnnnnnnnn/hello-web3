package ws

import (
	"encoding/json"
	"errors"
	"pledge-backend/api/models/kucoin"
	"pledge-backend/config"
	"pledge-backend/log"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

const SuccessCode = 0
const PongCode = 1
const ErrorCode = -1

type Server struct {
	sync.Mutex
	Id     string
	Socket *websocket.Conn
	Send   chan []byte
	// 最后发送消息时间
	LastTime int64
}

type ServerManager struct {
	Servers    sync.Map
	Broadcast  chan []byte
	Register   chan *Server
	Unregister chan *Server
}

type Message struct {
	Code int    `json:"code"`
	Data string `json:"data"`
}

var Manager = ServerManager{}
var UserPingPongDurTime = config.Config.Env.WssTimeoutDuration // seconds

func (s *Server) SendToClient(data string, code int) {
	s.Lock()
	defer s.Unlock()
	dataBytes, err := json.Marshal(Message{
		Code: code,
		Data: data,
	})
	if err != nil {
		log.Logger.Sugar().Error(s.Id+" SendToClient err ", err)
	}
	err = s.Socket.WriteMessage(websocket.TextMessage, dataBytes)
	if err != nil {
		log.Logger.Sugar().Error(s.Id+" SendToClient err ", err)
	}
}

func (s *Server) ReadAndWrite() {
	// 异常通道
	errChan := make(chan error)

	// 管理链接
	Manager.Servers.Store(s.Id, s)

	// 关闭资源
	defer func() {
		Manager.Servers.Delete(s)
		_ = s.Socket.Close()
		close(s.Send)
	}()

	// 写
	go func() {
		for {
			// 监听发送通道
			message, ok := <-s.Send
			if !ok {
				errChan <- errors.New("write message error")
				return
			}
			s.SendToClient(string(message), SuccessCode)
		}
	}()

	// 读
	go func() {
		for {
			// 读取消息
			_, message, err := s.Socket.ReadMessage()
			if err != nil {
				log.Logger.Sugar().Error(s.Id+" ReadMessage err ", err)
				errChan <- err
				return
			}
			// 更新心跳时间
			if string(message) == "ping" || string(message) == `"ping"` || string(message) == "'ping'" {
				s.LastTime = time.Now().Unix()
				s.SendToClient("pong", PongCode)
			}
			continue
		}
	}()

	// 心跳检测
	for {
		select {
		case <-time.After(time.Second):
			// 每秒执行，检查最后发送消息时间是否>=超时时间，超时return
			if time.Now().Unix()-s.LastTime >= UserPingPongDurTime {
				s.SendToClient("heartbeat timeout", ErrorCode)
				return
			}
		case err := <-errChan:
			// 监听异常通道，有异常return
			log.Logger.Sugar().Error(s.Id, " ReadAndWrite returned ", err)
			return
		}
	}
}

// 开启websocket
func StartServer() {
	log.Logger.Info("WsServer start")
	for {
		price, ok := <-kucoin.PlgrPriceChan
		if ok {
			Manager.Servers.Range(func(key, value interface{}) bool {
				value.(*Server).SendToClient(price, SuccessCode)
				return true
			})
		}
	}
}
