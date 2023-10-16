const Native		= require("./Native.js");
const Client		= require("./Client.js");
const Emitter		= require("medooze-event-emitter");
const SharedPointer	= require("./SharedPointer.js")

/**
 * @typedef {Object} ApplicationEvents
 * @property {(self: Application) => void} stopped
 * @property {(client: Client) => void} connect
 */

/** @extends {Emitter<ApplicationEvents>} */
class Application extends Emitter
{
	constructor()
	{
		//instantiate mitter
		super();
		
		//Create native server
		this.application = new Native.RTMPApplicationImpl(this);
		
		//Client map
		this.clients = /** @type {Map<string, Client>} */ (new Map());
		
		//The event handler
		this.onconnect = (
			/** @type {string} */ peerIp,
			/** @type {number} */ peerPort,
			/** @type {string} */ appName,
			/** @type {Native.RTMPNetConnectionImplShared} */ conn,
		) =>{
			//Create new connection
			const client = new Client(SharedPointer(conn),peerIp,peerPort,appName);
			//Add to client list
			this.clients.set(client.getId(),client);
			//event handlers
			client.once("stopped",()=>{
				//Remove client from map
				this.clients.delete(client.getId());
			});
			//Emit event
			this.emit("connect",client);
		};
	}
	
	
	stop()
	{
		//Stop clients
		for (const [clientId,client] of this.clients)
			//Stop it
			client.stop();
		
		//Emit stopped
		this.emit("stopped",this);
		
		//Close emitter
		super.stop();
		
	}
}

module.exports = Application;
