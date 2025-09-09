package tasks

import (
	"pledge-backend/db"
	"pledge-backend/task/common"
	"pledge-backend/task/services"
	"time"

	"github.com/jasonlvhit/gocron"
)

func Task() {

	// 获取环境变量
	common.GetEnv()

	// 刷新Redis
	err := db.RedisFlushDB()
	if err != nil {
		panic("clear redis error " + err.Error())
	}

	// 初始化执行
	services.NewPool().UpdateAllPoolInfo()
	services.NewTokenPrice().UpdateContractPrice()
	services.NewTokenSymbol().UpdateContractSymbol()
	services.NewTokenLogo().UpdateTokenLogo()
	services.NewBalanceMonitor().Monitor()
	// services.NewTokenPrice().SavePlgrPrice()
	services.NewTokenPrice().SavePlgrPriceTestNet()

	// 声明Scheduler
	s := gocron.NewScheduler()
	s.ChangeLoc(time.UTC)
	// 注册任务
	_ = s.Every(2).Minutes().From(gocron.NextTick()).Do(services.NewPool().UpdateAllPoolInfo)
	_ = s.Every(1).Minute().From(gocron.NextTick()).Do(services.NewTokenPrice().UpdateContractPrice)
	_ = s.Every(2).Hours().From(gocron.NextTick()).Do(services.NewTokenSymbol().UpdateContractSymbol)
	_ = s.Every(2).Hours().From(gocron.NextTick()).Do(services.NewTokenLogo().UpdateTokenLogo)
	_ = s.Every(30).Minutes().From(gocron.NextTick()).Do(services.NewBalanceMonitor().Monitor)
	// _ = s.Every(30).Minutes().From(gocron.NextTick()).Do(services.NewTokenPrice().SavePlgrPrice)
	_ = s.Every(30).Minutes().From(gocron.NextTick()).Do(services.NewTokenPrice().SavePlgrPriceTestNet)
	// 启动
	<-s.Start()

}
