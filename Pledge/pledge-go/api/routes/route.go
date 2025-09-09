package routes

import (
	"pledge-backend/api/controllers"
	"pledge-backend/api/middlewares"
	"pledge-backend/config"

	"github.com/gin-gonic/gin"
)

// 初始化路由
func InitRoute(e *gin.Engine) *gin.Engine {

	// 版本分组
	v2Group := e.Group("/api/v" + config.Config.Env.Version)

	//====================================== web ======================================

	// 借贷池
	poolController := controllers.PoolController{}
	v2Group.GET("/poolBaseInfo", poolController.PoolBaseInfo)
	v2Group.GET("/poolDataInfo", poolController.PoolDataInfo)
	v2Group.GET("/token", poolController.TokenList)
	v2Group.POST("/pool/debtTokenList", middlewares.CheckToken(), poolController.DebtTokenList)
	v2Group.POST("/pool/search", middlewares.CheckToken(), poolController.Search)

	// 价格
	priceController := controllers.PriceController{}
	v2Group.GET("/price", priceController.NewPrice)

	//====================================== admin ======================================

	// 多签
	multiSignPoolController := controllers.MultiSignPoolController{}
	v2Group.POST("/pool/setMultiSign", middlewares.CheckToken(), multiSignPoolController.SetMultiSign) //multi-sign set
	v2Group.POST("/pool/getMultiSign", middlewares.CheckToken(), multiSignPoolController.GetMultiSign) //multi-sign get

	// 用户
	userController := controllers.UserController{}
	v2Group.POST("/user/login", userController.Login)                             // login
	v2Group.POST("/user/logout", middlewares.CheckToken(), userController.Logout) // logout

	return e
}
