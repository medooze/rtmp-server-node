const Native = require("./Native");
const Emitter = require("medooze-event-emitter");
const Status = require("./Status");
const OutgoingStreamBridge = require("./OutgoingStreamBridge.js")

/**
 * @typedef {Object} ClientConnectionEvents
 * @property {(self: ClientConnection) => void} connected
 * @property {(self: ClientConnection) => void} disconnected 
 * @property {(self: ClientConnection) => void} stopped
 * @property {(self: ClientConnection, name: string, cmd: any[]) => void} cmd
 */


/** @extends {Emitter<ClientConnectionEvents>} */
class ClientConnection extends Emitter
{
	constructor()
	{
		//Init emitter
		super()
		this.streams = new Map();
		this.maxStreamId = 0;

		//Create neative connection
		this.connection = new Native.RTMPClientConnectionImpl(this);

		this.onconnected = () =>
		{
			//Check if already stopped
			if (this.stopped)
				//Do nothing
				return;

			//Emit event
			this.emit("connected", this);
		};

		this.oncmd =  (streamId, name, cmd) => {
			//Check if already stopped
			if (this.stopped)
				//Do nothing
				return;

			//IF the command is from a stream
			if (streamId)
			{
				//Get stream for id
				const stream = this.streams.get(streamId);

				//Emit event on stream
				if (stream)
					stream.emit("cmd", stream, name, cmd);
			} else {
				//Emit event
				this.emit("cmd", this, name, cmd);
			}
		}

		this.ondisconnected = () =>
		{
			//Check if already stopped
			if (this.stopped)
				//Do nothing
				return;

			//Emit event		
			this.emit("disconnected", this);
			//Stop us
			this.stop();
		};
	}

	connect(server, port, app)
	{
		this.connection.Connect(server, port, app);
	}


	async publish(url, params)
	{
		//Create RTMP stream and get streamId
		const [,streamId] = await new Promise((resolve,reject) => this.connection.CreateStream({resolve,reject}));
		//Send publish cmd for stream
		this.connection.Publish(streamId, url);
		//Create new outgoingstream
		const outgoingStream = new OutgoingStreamBridge(streamId, this.connection);

		//LIsten for
		outgoingStream.once("stopped", () => {
			//If we are not yet stopped
			if (!this.stopped)
				//Send delete stream cmd, but don't wait for its resolution
				new Promise((resolve,reject) => this.connection.DeleteStream(streamId, {resolve,reject}));
			//Remove
			this.streams.delete(streamId);
		});

		//Store
		this.streams.set(streamId, outgoingStream);

		//Create new 
		return outgoingStream;
	}

	stop()
	{
		//Check not already stopped
		if (this.stopped)
			//Done
			return;

		//Remove us as listener
		this.stopped = true;
		
		//Stop all streams
		for (const [streamId,stream] of this.streams)
			stream.stop();

		//Emit stopped event
		this.emit("stopped", this);

		//Stop native connection
		this.connection.Stop();

		//Stop emitter
		super.stop();

		//Clear stuff
		//@ts-expect-error
		this.connection = null;
	}
}

module.exports = ClientConnection;