const RTMPServer		= require("../index.js");

RTMPServer.enableLog(true);
RTMPServer.enableDebug(true);
RTMPServer.enableUltraDebug(true);

//Try to clean up on exit
const onExit = (e) =>
{
	if (e) console.error(e);
	RTMPServer.terminate();
	process.exit();
};

process.on("uncaughtException", onExit);
process.on("SIGINT", onExit);
process.on("SIGTERM", onExit);
process.on("SIGQUIT", onExit);

//Create server and app
const app = RTMPServer.createApplication();
const rtmp = RTMPServer.createServer();

const key = "test";
const server = "localhost";
const port = 1935;
const appName = "v2/pub";

app.on("connect", (client) =>
{
	console.log("client connected");

	//Create client connection
	const connection = RTMPServer.createClientConnection();

	//Add publish listener
	client.on("stream", (stream) =>
	{
		console.log("client got new stream");

		//Listen for commands
		stream.on("cmd",async(cmd, transId, ...params) => {

			console.log("got command from client", cmd.name);

			if (cmd.name == "publish")
			{
				//Create incoming stream
				const incomingStream = stream.createIncomingStreamBridge();
				//Started
				stream.sendStatus(transId, RTMPServer.NetStream.Publish.Start);
				//Start restreaming when connected
				connection.on("connected",async ()=>{
					console.log("restreamer connection connected, publishing");

					const outgoingStream = await connection.publish(key);

					outgoingStream.attachTo(incomingStream);

					console.log("restreamer connection connected");
				});
			
				//Connect to restream server
				connection.connect(server, port, appName);
			}
		})
	});

	connection.on("disconnected",()=>{
		console.log("client disconnected");
	});

	client.on("stopped",()=>{
		connection.stop();
	});
	//Accept client connection by default
	client.accept();
});

//Start rtmp server
rtmp.addApplication("restream", app);
rtmp.start(1936);
	

