const uuidV4		= require("uuid/v4");
const Emitter		= require("./Emitter");
const Stream		= require("./Stream");

class Client extends Emitter
{
	constructor(connection,appName)
	{
		//Init emitter
		super();
		//Create new id
		this.id = uuidV4();
		//Get app name from request url
		this.appName = appName;
		//Store native connection
		this.connection = connection;
		//Map of streams
		this.streams = new Map();
		
		//Events
		this.onstream = (netstream)=>{
			//Create stream wrapper
			const stream = new Stream(netstream);
			//Add to stream
			this.streams.set(0,stream);
			//Emit event
			this.emitter.emit("stream",stream);
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
		//Launche stopped event
		this.emitter.emit("stopped",this);
		
		//Stop emitter
		super.stop();
		//Release mem
		this.connection = null;
	}
}

module.exports = Client;
