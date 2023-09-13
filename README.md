[![rtmp-server-node-test](https://github.com/medooze/rtmp-server-node/actions/workflows/release.yaml/badge.svg)](https://github.com/medooze/rtmp-server-node/actions/workflows/release.yaml)

# rtmp-server-node

RTMP server for node

## Install
 
Just add the Medooze media server as a dependency to your node proyect:
```
    npm i --save rtmp-media-server
```

## Example

```
const brige	= RTMPServer.createIncomingStreamBridge();
const demo	= RTMPServer.createApplication();
const rtmp	= RTMPServer.createServer();

rtmp.addApplication("demo",demo);
rtmp.start(1935);

demo.on("connect",(client)=>{
	console.log("connected on "+client.getAppName());
	
	client.on("stream",(stream)=>{
		console.log("got stream ",stream.getId());
		
		stream.on("cmd",(cmd,...params)=>{
			console.log("got cmd "+cmd.name,params);
			
			if (cmd.name=="publish")
			{
				try { 
					//Start publishing
					stream.attachTo(brige);
					///Started
					stream.sendStatus(RTMPServer.NetStream.Publish.Start);
				} catch (e) {
					//Log it
					console.error(e);
					//Errror
					stream.sendStatus(RTMPServer.NetStream.Failed,e.toString());
				}
			}
		});
		
		stream.on("stopped",()=>{
			console.log("stream stopped");
		});
	});
	
	client.accept();
});

```

## Author

Sergio Garcia Murillo @ Medooze 

## Contributing
To get started, [Sign the Contributor License Agreement](https://www.clahub.com/agreements/medooze/media-server-node").

## License
MIT
