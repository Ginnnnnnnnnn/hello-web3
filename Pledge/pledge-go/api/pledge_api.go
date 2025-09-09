package main

import (
	"pledge-backend/api/middlewares"
	"pledge-backend/api/models"
	"pledge-backend/api/models/kucoin"
	"pledge-backend/api/models/ws"
	"pledge-backend/api/routes"
	"pledge-backend/api/static"
	"pledge-backend/api/validate"
	"pledge-backend/config"
	"pledge-backend/db"

	"github.com/gin-gonic/gin"
)

// 如果更改版本，则需要修改以下文件
// config/init.go
func main() {

	// 初始化mysql
	db.InitMysql()

	// 初始化redis
	db.InitRedis()

	// 初始化表结构
	models.InitTable()

	// 绑定验证器
	validate.BindingValidator()

	// 开启websocket
	go ws.StartServer()

	// 从kucoin交易所获取plgr价格
	go kucoin.GetExchangePrice()

	// 设置启动模式
	gin.SetMode(gin.ReleaseMode)
	app := gin.Default()
	// 设置静态服务器
	staticPath := static.GetCurrentAbPathByCaller()
	app.Static("/storage/", staticPath)
	// 设置跨域
	app.Use(middlewares.Cors())
	// 初始化路由
	routes.InitRoute(app)
	// 启动程序
	_ = app.Run(":" + config.Config.Env.Port)

}
