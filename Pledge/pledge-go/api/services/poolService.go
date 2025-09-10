package services

import (
	"pledge-backend/api/common/statecode"
	"pledge-backend/api/models"
	"pledge-backend/log"
)

type poolService struct{}

func NewPool() *poolService {
	return &poolService{}
}

// 查询借贷池信息
func (s *poolService) PoolBaseInfo(chainId int, result *[]models.PoolBaseInfoRes) int {
	// 查询借贷池信息
	err := models.NewPoolBases().PoolBaseInfo(chainId, result)
	if err != nil {
		log.Logger.Error(err.Error())
		return statecode.CommonErrServerErr
	}
	return statecode.CommonSuccess
}

// 查询数据信息
func (s *poolService) PoolDataInfo(chainId int, result *[]models.PoolDataInfoRes) int {
	// 查询数据信息
	err := models.NewPoolData().PoolDataInfo(chainId, result)
	if err != nil {
		log.Logger.Error(err.Error())
		return statecode.CommonErrServerErr
	}
	return statecode.CommonSuccess
}
