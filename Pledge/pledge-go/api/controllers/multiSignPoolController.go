package controllers

import (
	"pledge-backend/api/common/statecode"
	"pledge-backend/api/models/request"
	"pledge-backend/api/models/response"
	"pledge-backend/api/services"
	"pledge-backend/api/validate"
	"pledge-backend/log"

	"github.com/gin-gonic/gin"
)

type MultiSignPoolController struct {
}

// 多签名钱包-设置
func (c *MultiSignPoolController) SetMultiSign(ctx *gin.Context) {
	res := response.Gin{Res: ctx}
	req := request.SetMultiSign{}
	log.Logger.Sugar().Info("SetMultiSign req ", req)
	// 处理参数
	errCode := validate.NewMutiSign().SetMultiSign(ctx, &req)
	if errCode != statecode.CommonSuccess {
		res.Response(ctx, errCode, nil)
		return
	}
	//
	errCode, err := services.NewMutiSign().SetMultiSign(&req)
	if errCode != statecode.CommonSuccess {
		log.Logger.Error(err.Error())
		res.Response(ctx, errCode, nil)
		return
	}
	// 响应
	res.Response(ctx, statecode.CommonSuccess, nil)
}

// 多签名钱包-查询
func (c *MultiSignPoolController) GetMultiSign(ctx *gin.Context) {
	res := response.Gin{Res: ctx}
	req := request.GetMultiSign{}
	result := response.MultiSign{}
	log.Logger.Sugar().Info("GetMultiSign req ", nil)
	// 处理参数
	errCode := validate.NewMutiSign().GetMultiSign(ctx, &req)
	if errCode != statecode.CommonSuccess {
		res.Response(ctx, errCode, nil)
		return
	}
	// 查询多签名钱包
	errCode, err := services.NewMutiSign().GetMultiSign(&result, req.ChainId)
	if errCode != statecode.CommonSuccess {
		log.Logger.Error(err.Error())
		res.Response(ctx, errCode, nil)
		return
	}
	// 响应
	res.Response(ctx, statecode.CommonSuccess, result)
}
