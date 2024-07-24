class CommandError extends Error
{
	/**
	 * @param {string} commandName
	 * @param {unknown} value
	 */
	constructor(commandName, value)
	{
		super(`RTMP command ${commandName} failed: ${JSON.stringify(value)}`);
		this.name = CommandError.name;
		this.commandName = commandName;
		this.value = value;
	}
}

module.exports = CommandError;
