const Native		= require("./Native.js");
const Client		= require("./Client.js");
const Emitter		= require("./Emitter.js");
const SharedPointer	= require("./SharedPointer.js")

class Application extends Emitter
{
	constructor()
	{
		//instantiate mitter
		super();
		
		//Create native server
		this.application = new Native.RTMPApplicationImpl(this);
		
		//Client map
		this.clients = new Map();
		
		//The event handler
		this.onconnect = (appName,conn) =>{
			//Create new connection
			const client = new Client(SharedPointer(conn),appName);
			//Add to client list
			this.clients.set(client.getId(),client);
			//event handlers
			client.once("stopped",(client)=>{
				//Remove client from map
				this.clients.delete(client.getId());
			});
			//Emit event
			this.emitter.emit("connect",client);
		};
	}
	
	
	stop()
	{
		//Stop clients
		for (const [clientId,client] of this.clients)
			//Stop it
			client.stop();
		
		//Emit stopped
		this.emitter.emit("stopped",this);
		
		//Close emitter
		super.stop();
		
	}
}

module.exports = Application;
