package main

import (
	"pledge-backend/db"
	"pledge-backend/task/models"
	"pledge-backend/task/tasks"
)

// 如果更改版本，则需要修改以下文件
// config/init.go
func main() {

	// 初始化 mysql
	db.InitMysql()

	// 初始化 redis
	db.InitRedis()

	// 初始化表结构
	models.InitTable()

	// 启动任务
	tasks.Task()

}
