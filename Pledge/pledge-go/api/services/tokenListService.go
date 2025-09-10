package services

import (
	"pledge-backend/api/common/statecode"
	"pledge-backend/api/models"
	"pledge-backend/api/models/request"
)

type TokenList struct{}

func NewTokenList() *TokenList {
	return &TokenList{}
}

// 查询债务代币列表
func (c *TokenList) DebtTokenList(req *request.TokenList) (int, []models.TokenInfo) {
	res, err := models.NewTokenInfo().GetTokenInfo(req)
	if err != nil {
		return statecode.CommonErrServerErr, nil
	}
	return statecode.CommonSuccess, res

}

// 查询代币信息
func (c *TokenList) GetTokenList(req *request.TokenList) (int, []models.TokenList) {
	tokenList, err := models.NewTokenInfo().GetTokenList(req)
	if err != nil {
		return statecode.CommonErrServerErr, nil
	}
	return statecode.CommonSuccess, tokenList
}
