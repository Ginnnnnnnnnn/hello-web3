package router

import (
	"time"

	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"

	"github.com/ProjectsTask/EasySwapBackend/src/api/middleware"

	"github.com/ProjectsTask/EasySwapBackend/src/service/svc"
)

func NewRouter(svcCtx *svc.ServerCtx) *gin.Engine {
	gin.ForceConsoleColor()
	gin.SetMode(gin.ReleaseMode)
	// 新建一个gin引擎实例
	r := gin.New()
	// 使用恢复中间件
	r.Use(middleware.RecoverMiddleware())
	// 使用日志中间件
	r.Use(middleware.RLog())
	// 使用cors中间件
	r.Use(cors.New(cors.Config{
		AllowAllOrigins:  true,
		AllowMethods:     []string{"GET", "POST", "PUT", "DELETE", "OPTIONS", "PATCH"},
		AllowHeaders:     []string{"Origin", "Content-Length", "Content-Type", "X-CSRF-Token", "Authorization", "AccessToken", "Token"},
		ExposeHeaders:    []string{"Content-Length", "Content-Type", "Access-Control-Allow-Origin", "Access-Control-Allow-Headers", "X-GW-Error-Code", "X-GW-Error-Message"},
		AllowCredentials: true,
		MaxAge:           1 * time.Hour,
	}))
	// 加载v1路由
	loadV1(r, svcCtx)
	// 返回
	return r
}
