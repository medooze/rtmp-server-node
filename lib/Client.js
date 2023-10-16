const { v4: uuidV4 }	= require("uuid");
const Emitter		= require("medooze-event-emitter");
const Stream		= require("./Stream");
const SharedPointer	= require("./SharedPointer.js");
const Native		= require("./Native");


/**
 * @typedef {Object} ClientEvents
 * @property {(self: Client) => void} stopped
 * @property {(stream: Stream) => void} stream
 */

/** @extends {Emitter<ClientEvents>} */
class Client extends Emitter
{
	constructor(
		/** @type {Native.RTMPNetConnectionImpl} */ connection,
		/** @type {string} */ peerIp,
		/** @type {number} */ peerPort,
		/** @type {string} */ appName)
	{
		//Init emitter
		super();
		//Create new id
		this.id = uuidV4();
		//Get peer address
		this.peerIp = peerIp;
		this.peerPort = peerPort;
		//Get app name from request url
		this.appName = appName;
		//Store native connection
		this.connection = connection;
		//Map of streams
		this.streams = /** @type {Map<number, Stream>} */ (new Map());
		//Ids
		this.maxId = 0;
		
		//Events
		this.onstream = (/** @type {Native.RTMPNetStreamImplShared} */ netstream)=>{
			//Create stream wrapper
			const stream = new Stream(SharedPointer(netstream));
			//New id
			const id = this.maxId++;
			//Add to stream
			this.streams.set(id,stream);
			//Listen for stopped event
			stream.once("stopped",()=>{
				//Delete from set
				this.streams.delete(id);
			});
			//Emit event
			this.emit("stream",stream);
		};
		this.ondisconnect = ()=>{
			//NO connection anymore
			//@ts-expect-error
			this.connection = false;
			//Stop us
			this.stop();
		};
		
		
	}
	
	getId()
	{
		return this.id;
	}
	
	getAppName()
	{
		return this.appName;
	}
	
	accept()
	{
		//Accept and pass us as listener
		this.connection.Accept(this);
	}
	
	reject()
	{
		//Reject
		this.connection.Reject();
		//Stop
		this.stop();
	}
	
	stop()
	{
		//If already stopped
		if (!this.streams)
			//Do nothing
			return;
		
		//If got connection
		if (this.connection)
			//Disconnect connection
			this.connection.Disconnect();
		
		//Stop all stream
		for (const [id,stream] of this.streams)
			//Stop it
			stream.stop();
		
		//Launche stopped event
		this.emit("stopped",this);
		
		//Stop emitter
		super.stop();
		//Release mem
		//@ts-expect-error
		this.connection = null;
		//@ts-expect-error
		this.streams = null;
	}
}

module.exports = Client;
