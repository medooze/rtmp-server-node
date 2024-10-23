const tap			= require("tap");
const RTMPServer		= require("../index.js");
const { exec }			= require("child_process")

function ffmpeg(args)
{
	let child;
	//Run ffmpeg cmd
	const promise = new Promise((resolve, reject) =>
	{
		//Start ffmpeg
		child = exec("ffmpeg " + args, {}, (res) => {
			if (res.error)
				reject(res.error)
			else if (res.code)
				reject(res.code)
			else
				resolve();
		});
	});
	//Add stop method
	promise.stop = async () =>
	{
		child.kill();
		//await promise;
	}
	return promise;
}


RTMPServer.enableWarning(false);
RTMPServer.enableLog(false);
RTMPServer.enableDebug(false);
RTMPServer.enableUltraDebug(false);

//Try to clean up on exit
const onExit = (e) =>
{
	if (e) console.error(e);
	process.exit();
};

function sleep(ms)
{
	return new Promise(resolve => setTimeout(resolve, ms));
}

function promise()
{
	let resolve;
	let reject;
	const promise = new Promise((_resolve, _reject) => {
		resolve = _resolve;
		reject = _reject;
	});
	promise.resolve = resolve;
	promise.reject = reject;
	return promise;
}

function ffmpeg(args)
{
	let child;
	//Run ffmpeg cmd
	const promise = new Promise((resolve, reject) =>
	{
		//Start ffmpeg
		child = exec("ffmpeg " + args, {}, (res) => {
			if (res.error)
				reject(res.error)
			else if (res.code)
				reject(res.code)
			else
				resolve();
		});
	});
	//Add stop method
	promise.stop = async () =>
	{
		child.kill();
		//await promise;
	}
	return promise;
}


process.on("uncaughtException", onExit);
process.on("SIGINT", onExit);
process.on("SIGTERM", onExit);
process.on("SIGQUIT", onExit);

function args(stream, token)
{
	return '-f lavfi -i testsrc=size=vga:rate=30 -f lavfi -i sine=frequency=1000 -c:v libx264 -preset ultrafast -tune zerolatency -profile:v baseline -level 3.1 -bf 0 -g 60 -c:a aac -b:v 2500k -b:a 128k -f flv -pix_fmt yuv420p' +
		' -rtmp_playpath "' + token + '"' +
		' -rtmp_live live "rtmp://127.0.0.1/test/'+stream+'"'; 
}
	

tap.test("Server", async function (suite)
{

	await suite.test("start+stop", async function (test)
	{
		//Create server and app
		const app = RTMPServer.createApplication();
		const rtmp = RTMPServer.createServer();

		//Start rtmp server
		rtmp.addApplication("test", app);
		rtmp.start(1935);
		//Stop server
		rtmp.stop();
		
		//OK
		test.end();
	});
	
	await suite.test("publish+unpublish", async function (test)
	{
		test.plan(2);

		//Create server and app
		const app = RTMPServer.createApplication();
		const rtmp = RTMPServer.createServer();

		let connected = promise();
		app.on("connect", (client) =>
		{
			//Add publish listener
			client.on("stream", (stream) =>
			{
				//Create incoming stream
				const incomingStream = stream.createIncomingStreamBridge();
				//Send to server
				test.ok(incomingStream);
				connected.resolve();
			});
			//Accept client connection by default
			client.accept();
		});

		//Start rtmp server
		rtmp.addApplication("test", app);
		rtmp.start(1935);

		//Start publishing rtmp
		const pub = ffmpeg(args("nane","token"));
		test.ok(pub);
		await connected;

		//Stop
		await pub.stop();

		//Stop server
		rtmp.stop();

		//OK
		test.end();
	});

	await suite.test("reject", async function (test)
	{
		test.plan(3);

		//Create server and app
		const app = RTMPServer.createApplication();
		const rtmp = RTMPServer.createServer();

		app.on("connect", (client) =>
		{
			//Reject
			client.reject();
			//Worked
			test.pass("RTMPconnection rejected sucessfully");
		});

		//Start rtmp server
		rtmp.addApplication("test", app);
		rtmp.start(1935);

		
		//Start publishing rtmp
		const pub = ffmpeg(args("nane","token"));

		test.ok(pub);

		//Should be rejected
		await pub.catch((e)=>test.pass("ffmpeg disconnected"));

		//Stop server
		rtmp.stop();

		//OK
		test.end();
	});

	await suite.test("publish+unpublish  maxLateOffset+maxBufferingTime", async function (test)
	{
		test.plan(2);

		//Create server and app
		const app = RTMPServer.createApplication();
		const rtmp = RTMPServer.createServer();

		let connected = promise();
		app.on("connect", (client) =>
		{
			//Add publish listener
			client.on("stream", (stream) =>
			{
				//Create incoming stream
				const incomingStream = stream.createIncomingStreamBridge(100,200);
				//Send to server
				test.ok(incomingStream);
				connected.resolve();
			});
			//Accept client connection by default
			client.accept();
		});

		//Start rtmp server
		rtmp.addApplication("test", app);
		rtmp.start(1935);

		//Start publishing rtmp
		const pub = ffmpeg(args("nane","token"));

		test.ok(pub);
		await connected;

		//Stop
		await pub.stop();

		//Stop server
		rtmp.stop();

		//OK
		test.end();
	});

	await suite.test("setTargetBitrateHint", async function (test)
	{
		test.plan(2);

		//Create server and app
		const app = RTMPServer.createApplication();
		const rtmp = RTMPServer.createServer();

		let connected = promise();
		app.on("connect", (client) =>
		{
			//Add publish listener
			client.on("stream", (stream) =>
			{
				//Create incoming stream
				const incomingStream = stream.createIncomingStreamBridge();
				//Get video track
				const incomingStreamTrack = incomingStream.getVideoTracks()[0];
				//Set bitrate hint
				incomingStreamTrack.setTargetBitrateHint(1000);
				//No error
				test.pass();
				connected.resolve();
			});
			//Accept client connection by default
			client.accept();
		});

		//Start rtmp server
		rtmp.addApplication("test", app);
		rtmp.start(1935);

		//Start publishing rtmp
		const pub = ffmpeg(args("nane","token"));

		test.ok(pub);
		await connected;

		//Stop
		await pub.stop();

		//Stop server
		rtmp.stop();

		//OK
		test.end();
	});

	await suite.test("stats+getRTT", async function (test)
	{
		test.plan(4);

		//Create server and app
		const app = RTMPServer.createApplication();
		const rtmp = RTMPServer.createServer();

		let connected = promise();
		app.on("connect", (client) =>
		{
			//Add publish listener
			client.on("stream", (stream) =>
			{
				//Create incoming stream
				const incomingStream = stream.createIncomingStreamBridge();
				//Get stats
				const stats = incomingStream.getStats();
				//Should be present
				test.ok(stats,"got stats");
				//Get rtt
				const rtt = stream.getRTT();
				//Rtt should be the same
				test.same(rtt,stats.audio[""].rtt,"rtt is the same for audio");
				test.same(rtt,stats.video[""].rtt,"rtt is the same dor video");
				connected.resolve();
			});
			//Accept client connection by default
			client.accept();
		});

		//Start rtmp server
		rtmp.addApplication("test", app);
		rtmp.start(1935);

		//Start publishing rtmp
		const pub = ffmpeg(args("nane","token"));

		test.ok(pub);
		await connected;

		//Stop
		await pub.stop();

		//Stop server
		rtmp.stop();

		//OK
		test.end();
	});

	await suite.test("stats+getRTT async", async function (test)
	{
		test.plan(4);

		//Create server and app
		const app = RTMPServer.createApplication();
		const rtmp = RTMPServer.createServer();

		let connected = promise();
		app.on("connect", (client) =>
		{
			//Add publish listener
			client.on("stream", async (stream) =>
			{
				//Create incoming stream
				const incomingStream = stream.createIncomingStreamBridge();
				//Get stats
				const stats = await incomingStream.getStatsAsync();
				//Should be present
				test.ok(stats,"got stats");
				//Get rtt
				const rtt = stream.getRTT();
				//Rtt should be the same
				test.same(rtt,stats.audio[""].rtt,"rtt is the same for audio");
				test.same(rtt,stats.video[""].rtt,"rtt is the same dor video");
				connected.resolve();
			});
			//Accept client connection by default
			client.accept();
		});

		//Start rtmp server
		rtmp.addApplication("test", app);
		rtmp.start(1935);

		//Start publishing rtmp
		const pub = ffmpeg(args("nane","token"));

		test.ok(pub);
		await connected;

		//Stop
		await pub.stop();

		//Stop server
		rtmp.stop();

		//OK
		test.end();
	});

	suite.end();

}).then(() =>
{
	RTMPServer.terminate();
});

