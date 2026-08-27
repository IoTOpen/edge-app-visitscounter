function resetTrigger(topic, payload, retained)
	local data = json:decode(payload)
	local topic_read = topic:gsub("^set/", "obj/")
	mq:pub(topic_read, json:encode({value=data.value, timestamp=edge:time()}))
end

function handleTrigger(topic, payload, retained)
	local data = json:decode(payload)
	if data == nil then
		print('Invalid payload received on topic ' .. topic)
		return
	end

	if data.value == nil or data.value == 0 then
		print('No value field or value 0 in payload on topic ' .. topic)
		return
	end

	last = lynx.apiCall("GET", "/api/v2/status/" .. app.installation_id .. "?topics=" .. topic .. '_summary')

	if last == nil or last[1] == nil then
		print('No summary data found for topic ' .. topic .. '_summary. Initializing to 0.')
		last_value = 0
	else
		last_value = last[1].value
	end	


	local new_value = data.value + last_value;
	mq:pub(topic .. '_summary', json:encode({value=new_value, timestamp=data.timestamp}))
end

function createCountSummaryFunction(device_id)
	local device = nil
	local fn = nil

	for _, dev in ipairs(devices) do
		if tostring(dev.id) == tostring(device_id) then
			device = dev
			break
		else
		end
	end

	if device == nil then
		print('Device with ID ' .. device_id .. ' not found.')
		return
	end	

	local topic_read = 'obj/lora/' .. device.meta.eui .. '/line_cross_counter_in_summary'
	local topic_write = 'set/lora/' .. device.meta.eui .. '/line_cross_counter_in_summary'

	for _, fn in ipairs(functions) do
		if fn.meta.topic_read == topic_read then
			return  -- Summary function already exists
		end
	end

	local summaryFunction = {
		type = 'counter_summary',
		meta = {
			device_id = device_id,
			name = device.meta.eui .. ' - Count Summary',
			topic_read = topic_read,
			topic_write = topic_write,
		},
	}

	local summaryFn = lynx.createFunction(summaryFunction)
	print('Created summary function for ' .. device.meta.eui)
end


function findFunctionsToMonitor ()
	for _, fn in ipairs(functions) do
		if fn.meta['lora_type'] ==  'line_cross_counter_in' then
			createCountSummaryFunction(fn.meta.device_id)
		end
	end
end

function setUpFunctions()
	findFunctionsToMonitor()
end

function onFunctionsUpdated()
	setUpFunctions()
end

function onStart()
	setUpFunctions()

	mq:sub('obj/lora/+/line_cross_counter_in', 0)
	mq:bind('obj/lora/+/line_cross_counter_in', handleTrigger)
	mq:sub('set/lora/+/line_cross_counter_in_summary', 0)
	mq:bind('set/lora/+/line_cross_counter_in_summary', resetTrigger)
end