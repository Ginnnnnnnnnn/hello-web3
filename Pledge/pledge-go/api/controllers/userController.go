package controllers

import (
	"pledge-backend/api/common/statecode"
	"pledge-backend/api/models/request"
	"pledge-backend/api/models/response"
	"pledge-backend/api/services"
	"pledge-backend/api/validate"
	"pledge-backend/db"

	"github.com/gin-gonic/gin"
)

type UserController struct {
}

// 用户-登录
func (c *UserController) Login(ctx *gin.Context) {
	res := response.Gin{Res: ctx}
	req := request.Login{}
	result := response.Login{}

	errCode := validate.NewUser().Login(ctx, &req)
	if errCode != statecode.CommonSuccess {
		res.Response(ctx, errCode, nil)
		return
	}

	errCode = services.NewUser().Login(&req, &result)
	if errCode != statecode.CommonSuccess {
		res.Response(ctx, errCode, nil)
		return
	}

	res.Response(ctx, statecode.CommonSuccess, result)
}

// 用户-登出
func (c *UserController) Logout(ctx *gin.Context) {
	res := response.Gin{Res: ctx}

	usernameIntf, _ := ctx.Get("username")

	//delete username in redis
	_, _ = db.RedisDelete(usernameIntf.(string))

	res.Response(ctx, statecode.CommonSuccess, nil)
}
