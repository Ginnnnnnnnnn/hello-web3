package main

import (
	"flag"
	_ "net/http/pprof"

	"github.com/ProjectsTask/EasySwapBackend/src/api/router"
	"github.com/ProjectsTask/EasySwapBackend/src/app"
	"github.com/ProjectsTask/EasySwapBackend/src/config"
	"github.com/ProjectsTask/EasySwapBackend/src/service/svc"
)

const (
	defaultConfigPath = "./config/config.toml"
)

func main() {
	// 加载配置
	conf := flag.String("conf", defaultConfigPath, "conf file path")
	flag.Parse()
	c, err := config.UnmarshalConfig(*conf)
	if err != nil {
		panic(err)
	}
	for _, chain := range c.ChainSupported {
		if chain.ChainID == 0 || chain.Name == "" {
			panic("invalid chain_suffix config")
		}
	}
	// 初始化服务上下文
	serverCtx, err := svc.NewServiceContext(c)
	if err != nil {
		panic(err)
	}
	// 初始化路由
	r := router.NewRouter(serverCtx)
	// 创建APP
	app, err := app.NewPlatform(c, r, serverCtx)
	if err != nil {
		panic(err)
	}
	// 启动
	app.Start()
}
