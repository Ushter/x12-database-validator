local segValidate = {}

local family_tree = {}
local DBHelper = require 'X12_270.dbHelper'
local dbCache = require 'X12.querycache'
local cfg = require 'X12_270.Config'
local dbprefix = cfg.dbprefix

--Function to Generate error table with IK3 contents for 999
local function generate_error_table(error_table, segment, position, code, group)

   table.insert(error_table, {
         segID = segment,
         segPosition = position,
         errorCode = code,
         loopIDCode = group
      })

   return error_table
end

--Split string message Segment into individual entries based on *
--Also accomodate segments identfer such as ABK:123 to grab first 3 identofer values
local function SplitSegment(segment)
   local split = {}
   segment = segment .. "*"
   for part in string.gmatch(segment, "(.-)%*") do
      -- Check if the part contains ":" and further split if needed
      if string.match(part, ":") then
         -- If there is a ":", split by ":" and add each sub-part individually
         for subpart in string.gmatch(part, "([^:]+)") do
            table.insert(split, subpart)
         end
      else
         -- Otherwise, just insert the part as it is
         table.insert(split, part)
      end
   end

   return split
end

--Extract infromation from each message split
--USE the DB to verify message group identifier and index
--Ensure Message is being grouped and analyzed appropriatly for grouping

local function extractSegments(segments, dataType)
   local results = {}
   local lastValidSegmentGroup = "TS"

   for i, segment in ipairs(segments) do
      local split = SplitSegment(segment)
      local segmentName = split[1]

      --Initial query to grab some information
      local query = "SELECT identity_index, segment_group, identifier_value, order_index FROM "
      .. dbprefix .. "Lookup_Segment_Listing_" .. dataType .. " WHERE segment_name = '"
      .. segmentName .. "' ORDER BY order_index;"
      local result = dbCache.query{
         sql = query,
         db = DBHelper.conn
      }

      local identityIndex
      local segmentGroup = nil
      local orderIndex
      local identifier

      --If Query Has more than one results perform additional queries
      --Based on Identifier values , positioning , index or lastValidSegment
      local identical_values = true
      if #result >1 then
         for i = 2, #result do
            local first_value = tonumber(result[1].identity_index:nodeValue())
            if tonumber(result[i].identity_index:nodeValue()) ~= first_value then
               identical_values = false  -- Set the flag to false if any value differs
            end
            if first_value == nil then
               identical_values = false
            end
         end

         ---Query if all of them hve identical values and results more than 1
         --Narrow them down with another query that uses identical values and last segment group

         if identical_values == true then

            identityIndex =  tonumber(result[1].identity_index:nodeValue())
            identifier =split[identityIndex +2]
            orderIndex = tonumber(result[1].order_index:nodeValue())
            --Query with known identifier or identity index if it not null

            local query_w_ID = [[
            SELECT s1.segment_group, s1.order_index, s1.identity_index
            FROM ]] .. dbprefix .. [[Lookup_Segment_Listing_]] .. dataType .. [[ s1
            JOIN ]] .. dbprefix .. [[Lookup_Segment_Listing_]] .. dataType .. [[ s2
            ON s1.segment_group = s2.segment_name
            WHERE s1.segment_name = ']] .. segmentName .. [['
            AND s2.segment_group = ']] .. lastValidSegmentGroup .. [['
            AND (s1.identifier_value = ']] .. identifier .. [['
            OR ('|' + s1.identifier_value + '|') LIKE '%|]] .. identifier .. [[|%');
            ]]
            local result_w_ID = dbCache.query{
               sql = query_w_ID,
               db = DBHelper.conn
            }

            if result_w_ID == false or #result_w_ID == 0 then

               --QUery with only identifier
               query_w_ID =[[
               SELECT segment_group, order_index, identity_index
               FROM ]] .. dbprefix .. [[Lookup_Segment_Listing_]] .. dataType .. [[
               WHERE segment_name = ']] .. segmentName .. [['
               AND (identifier_value = ']] .. identifier .. [['
               OR ('|' + identifier_value + '|') LIKE '%|]] .. identifier .. [[|%');
               ]]
               result_w_ID = dbCache.query{
                  sql = query_w_ID,
                  db = DBHelper.conn
               }

            end

            if result_w_ID and #result_w_ID ==1 then
               identityIndex = tonumber(result_w_ID[1].identity_index:nodeValue())
               segmentGroup = result_w_ID[1].segment_group:nodeValue()
               orderIndex = tonumber(result_w_ID[1].order_index:nodeValue())

            end

         elseif identical_values == false then

            --Target Query with non identifier
            local test_query = "SELECT s1.segment_group, s1.identifier_value, s1.order_index FROM "
            .. dbprefix .. "Lookup_Segment_Listing_" .. dataType .. " s1 JOIN "
            .. dbprefix .. "Lookup_Segment_Listing_" .. dataType .. " s2 ON s1.segment_group = s2.segment_name WHERE s1.segment_name ='"
            ..segmentName.."' AND s2.segment_group = '"..lastValidSegmentGroup.."';"
            local finalize_group = dbCache.query{
               sql = test_query,
               db = DBHelper.conn
            }
            --target query with same identifiers such as TRN that posess complications
            if finalize_group == false then
               local fallback_query = [[
               SELECT segment_group, identifier_value, order_index
               FROM ]] .. dbprefix .. [[Lookup_Segment_Listing_]] .. dataType .. [[
               WHERE segment_name = ']] .. segmentName .. [['
               AND identifier_value = ']] .. lastValidSegmentGroup .. [[';
               ]]
               local fallback_result = dbCache.query{
                  sql = fallback_query,
                  db = DBHelper.conn
               }

               --FOR EQ if it is out of place
               if fallback_result == false then
                  segmentGroup = result[1].segment_group:nodeValue()
                  identifier = result[1].identifier_value:nodeValue()
                  orderIndex = tonumber(result[1].order_index:nodeValue())
               else
                  segmentGroup = fallback_result[1].segment_group:nodeValue()
                  identifier = fallback_result[1].identifier_value:nodeValue()
                  orderIndex = tonumber(fallback_result[1].order_index:nodeValue())

               end
            elseif #finalize_group ==1 then
               segmentGroup = finalize_group[1].segment_group:nodeValue()
               identifier = finalize_group[1].identifier_value:nodeValue()
               orderIndex = tonumber(finalize_group[1].order_index:nodeValue())

            end
         end
      else
         identityIndex = tonumber(result[1].identity_index:nodeValue())
         segmentGroup = result[1].segment_group:nodeValue()
         orderIndex = tonumber(result[1].order_index:nodeValue())
         identifier = result[1].identifier_value:nodeValue()
      end

      --handle TRN Case
      if orderIndex ~=1 and segmentGroup ~= lastValidSegmentGroup then
         segmentGroup = lastValidSegmentGroup
      end

      if orderIndex == 1 then

         lastValidSegmentGroup = segmentGroup
      end
      if segmentName == 'SE' then
         segmentGroup = 'TS'
      end
      --Generate Value table
      table.insert(results, {
            segment = segmentName,
            identifier = identifier,
            group = segmentGroup or "UnknownGroup",
            Message_Index = i
         })

      --Set LoopCode/Segment Group based on first segments
   end
   return results

end

--Categorized extracted segments into groups
local function Create_Structure_By_Groups(inputSegments)
   local resultStructure = {}
   local currentGroup = nil
   local currentSubTable = nil

   for _, segment in ipairs(inputSegments) do
      if segment.group ~= currentGroup then
         currentGroup = segment.group
         currentSubTable = {group = currentGroup, segments = {}}
         table.insert(resultStructure, currentSubTable)
      end

      table.insert(currentSubTable.segments, segment)
   end

   return resultStructure
end

--If DB identifier Values contains a pipe denoting multiple options
--Function o narrow down and compare identities provided by the input
local function checkIdentityMatch(inputIdentifier, rowIdentity)
   if rowIdentity:find("|") then
      local values = {}
      for value in string.gmatch(rowIdentity, "[^|]+") do
         table.insert(values, value)
      end

      for _, value in ipairs(values) do
         if inputIdentifier == value then
            return true
         end
      end
   else
      return inputIdentifier == rowIdentity
   end

   return false
end

--Validating Order at Segment Level
--goes through each segment in a specific group to validate the order from the DB
-- Also Validates the repeating segment inside a loop/ segment group
local function Order_Validation(Group, Input, dataType)
   local query = "SELECT DISTINCT segment_name, identifier_value, optional, order_index, identity_index, max_repeat, repeating FROM "
   .. dbprefix .. "Lookup_Segment_Listing_" .. dataType
   .. " WHERE segment_group = '" .. Group .. "' AND segment_type = 'segment' ORDER BY order_index ASC;"
   local result = dbCache.query{
      sql = query,
      db = DBHelper.conn
   }

   local j = 1
   local extra = false

   for i = 1, #result do
      if Input[j] == nil then
         if tonumber(result[i].optional:nodeValue()) == 0 then
            return false, result[i].segment_name:nodeValue(), result[i].identifier_value:nodeValue(), j
         end
      else
         if result[i].segment_name:nodeValue() == Input[j].segment then
            local repeat_count = 0

            if tonumber(result[i].repeating:nodeValue()) == 1 then
               while j <= #Input and Input[j].segment == result[i].segment_name:nodeValue() do
                  repeat_count = repeat_count + 1
                  j = j + 1
               end

               if repeat_count > tonumber(result[i].max_repeat:nodeValue()) then
                  return false, result[i].segment_name:nodeValue(), result[i].identifier_value:nodeValue(), Input[j - 1].Message_Index
               end
            else
               if result[i].identity_index ~= nil then
                  local check_identity = checkIdentityMatch(Input[j].identifier, result[i].identifier_value:nodeValue())
                  if check_identity then
                     j = j + 1
                  else
                     return false, result[i].segment_name:nodeValue(), result[i].identifier_value:nodeValue(), Input[j].Message_Index
                  end
               else
                  j = j + 1
               end
            end
         else
            if tonumber(result[i].optional:nodeValue()) == 0 then
               return false, result[i].segment_name:nodeValue(), result[i].identifier_value:nodeValue(), Input[j].Message_Index
            end
         end
      end
   end

   if j <= #Input then
      extra = true
      return false, Input[j].segment, Input[j].identifier, Input[j].Message_Index, extra
   end
   return true
end

--function to find Segment if it is out of order
local function findSegmentEntry(segment, identifier, segmentTable)

   for _, entry in ipairs(segmentTable) do
      for _, seg in ipairs(entry.segments) do



         if segment == 'SE' then return segment, true  end
         if seg.segment == segment and seg.identifier == identifier then
            return segment, seg.Message_Index
         end
      end
   end
   return segment, nil
end

local function build_tree(data)
   local nodes = {}

   local function get_or_create_node(id, optional, segment)
      if not nodes[id] then
         nodes[id] = {id = id, optional = optional,segment = segment, children = {}}
      elseif optional ~= nil then
         nodes[id].optional = optional
      end
      return nodes[id]
   end

   for i = 1, #data do
      local row = data[i]
      local parent_id = tostring(row[2])
      local child_id = tostring(row[3])
      local optional = row[4]
      local segment = tostring(row.first_segment_name)

      local parent_node = get_or_create_node(parent_id)
      local child_node = get_or_create_node(child_id, optional, segment)

      table.insert(parent_node.children, child_node)
   end

   local root = nodes['TS']
   if not root then
      iguana.logWarning("Error: Root node 'TS' not found.")
   end

   return root, nodes  -- Return both the root and the nodes table
end

local function create_reference_table(nodes)
   local reference_table = {}

   for id, node in pairs(nodes) do
      reference_table[id] = {
         parent = nil,
         siblings = {},
         children = node.children
      }
   end

   -- Populate the parent and siblings
   for id, node in pairs(nodes) do
      for _, child in ipairs(node.children) do
         reference_table[child.id].parent = node
      end
   end

   for id, node in pairs(nodes) do
      local parent = reference_table[id].parent
      if parent then
         for _, sibling in ipairs(parent.children) do
            if sibling.id ~= id then
               table.insert(reference_table[id].siblings, sibling)
            end
         end
      end
   end

   return reference_table
end

local function validate_next_input(segment_info, nextInputGroup)
   local missing_required_child = nil  -- Track the missing required child
   local first_segment = nil  -- Get the first segment from segment_info

   -- Check for immediate children and their optional status
   for _, child in ipairs(segment_info.children) do
      if tonumber(child.optional:nodeValue()) == 0 then  -- If child is required
         if child.id == nextInputGroup then
            return true, child.id  -- Matched required child, return true and ID
         else
            first_segment = child.segment
            missing_required_child = child.id  -- Mark this child as required but missing
         end
      elseif child.id == nextInputGroup then  -- If child is optional and matches
         return true, child.id  -- Matched optional child, return true and ID
      end
   end

   -- If a required child is missing, return false and the missing child's ID and first segment
   if missing_required_child then
      return false, missing_required_child, first_segment
   end

   -- Check against parent
   if segment_info.parent and segment_info.parent.id == nextInputGroup then
      return true, segment_info.parent.id  -- Matched parent, return true and parent ID
   end

   -- Check against siblings
   for _, sibling in ipairs(segment_info.siblings) do
      if sibling.id == nextInputGroup then
         return true, sibling.id  -- Matched sibling, return true and sibling ID
      end
   end

   -- If no match, return HL error with nil ID
   return false, nil, first_segment  -- Return nil ID but include the first segment
end

-- Main Validation function to validate curent groups
--Report the missing identity segment if group is missing
--Generates the error table to be put in 999
local function Validate(inputSegment, dataType)
   local error_entry = {}
   local tree = {}
   local nodes = {}
   local skip_list = {}

   -- Query to fetch segment listings (result) from the database
   local query = [[SELECT s1.*, s2.segment_name AS first_segment_name
FROM ]] .. dbprefix .. [[Lookup_Segment_Listing_]] .. dataType .. [[ s1
LEFT JOIN ]] .. dbprefix .. [[Lookup_Segment_Listing_]] .. dataType .. [[ s2
ON s1.segment_name = s2.segment_group
WHERE s1.segment_type = 'group'
AND s2.segment_type = 'segment'
AND s2.order_index = 1
ORDER BY CASE
  WHEN s1.id = 132 THEN 142
  WHEN s1.id = 142 THEN 132
  ELSE s1.id
END, s1.id;]]
   local result = dbCache.query{
      sql = query,
      db = DBHelper.conn
   }
   local groupName = result[1].segment_group:S()
   local root, nodes = build_tree(result)
   local reference_table = create_reference_table(nodes)

   for j = 1, #inputSegment do
      local inputGroup = inputSegment[j].group

      if groupName == inputGroup then

         if j < #inputSegment and inputSegment[j].group ~= inputSegment[j+1].group then
            if inputGroup == 'TS' then
               local next_segment_group = result[1].segment_name:nodeValue()
               groupName = next_segment_group

            elseif  inputSegment[j+1].group == groupName then
               groupName = groupName
            else

               local nextInputGroup = inputSegment[j+1].group
               local segment_info = reference_table[nextInputGroup]
               local grouper = reference_table[inputGroup]

               local match, id, first_segment = validate_next_input(grouper, nextInputGroup)

               if match == true then

                  groupName = id
               elseif match ==false then
                  if id ~= nil then
                     error_entry = generate_error_table(error_entry, first_segment,
                        inputSegment[j].segments[1].Message_Index, 2 , id)
                  end

                  for x = j+1, #inputSegment do

                     if inputSegment[x].segments[1].segment == 'HL' then
                        groupName = inputSegment[x].group

                        break
                     end

                     table.insert(skip_list, x)
                  end
               end
            end
         end
      end
   end


   for l = 1, #inputSegment do

      local skip = false
    for _, value in ipairs(skip_list) do
        if l == value then
            skip = true
            break
        end
    end

      if inputSegment[l].segments[1].segment ~='SE' and not skip then

         local status, segment, identity, position, extra = Order_Validation(inputSegment[l].group, inputSegment[l].segments, dataType)
         if extra == true then
            error_entry = generate_error_table(error_entry,segment, position, 3 , inputSegment[l].group)

         end

         if status == false and extra == nil then
            local segment, entry = findSegmentEntry(segment, identity, inputSegment)

            if entry ~= true then
               if entry == nil then
                  error_entry = generate_error_table(error_entry,segment, position, 2 , inputSegment[l].group)

               else
                  error_entry = generate_error_table(error_entry,segment, entry, 3 , inputSegment[l].group)

               end
            end
         end

      end
   end

   if #error_entry > 0 then
      return false, error_entry
   end

   return true
end

local function removeDuplicates(errorTable)
   local uniqueEntries = {}
   local filteredTable = {}
   for _, entry in ipairs(errorTable) do
      local key = entry.loopIDCode .. "-" .. entry.segPosition .. "-" .. entry.errorCode
      if not uniqueEntries[key] then
         table.insert(filteredTable, entry)
         uniqueEntries[key] = true
      end
   end

   return filteredTable
end

--------------
local function DB(loop_code)
   local dataType = '270'
   local query = "SELECT * FROM "..dbprefix.."Lookup_Segment_Listing_"
   ..dataType.." WHERE segment_type = 'group' ORDER BY CASE WHEN id = 132 THEN 142 WHEN id = 142 THEN 132 ELSE id END, id;"
   local return_value = dbCache.query{
      sql = query,
      db = DBHelper.conn
   }

   for i=1, #return_value do
      if return_value[i].segment_name:S() == loop_code then
         return return_value[i]
      end

   end
   return nil

end

local function validate_Repeat(loop_code,number_of_repeats)

   local conn = DB(loop_code)
   local max = tonumber(conn.max_repeat:S())
   local min = 0

   if tonumber(conn.repeating:S()) == 1 then
      min = 1
      if max == 0 then
         max = 999999
      end
   else
      max = 1
      min = 1
   end

   if number_of_repeats > max or number_of_repeats < min then
      return false,max+1
   end

   return true
end

local function process_repeat(data)

   local isValid= true
   local num_node = #data

   for i = 1 ,num_node do
      local isSegmentGroup = data[i]:nodeType()
      if isSegmentGroup == 'segment_group_repeated' and data[i]:S() ~= '' then
         isValid = validate_Repeat(data[i]:nodeName(),#data[i])

      end
   end
   return isValid
end

--Main Function to pass the message in the workflow
--And obtain the table of error messages
function segValidate.tsSegmentStructure(tsMsg, dataType)
   assert(type(tsMsg) == 'string', 'Message must be a string')
   assert(type(dataType) == 'string' and dataType:match('^%d%d%d$'),
      'Transaction type must contain three digits')

   local result = {}
   local current_group = nil
   tsMsg = 'ST*'..dataType..tsMsg

   local split_data = tsMsg:split('~')
   local extractedData = extractSegments(split_data, dataType)

   local Partition = Create_Structure_By_Groups(extractedData)
   local parse_for_Repeat= x12.parse{vmd='x12_270_5010_V1_Repeating.vmd',data=tsMsg}
   local validate_repeat_group = process_repeat(parse_for_Repeat.IE.FG[1].TS[1])

   local IsValidated, segErrorList= Validate(Partition, dataType)
   if validate_repeat_group == false then
      table.insert(segErrorList, validate_repeat_group)

   end
   if IsValidated ==false then
      local final_error_table = removeDuplicates(segErrorList)
      return IsValidated, final_error_table

   end

   return IsValidated, segErrorList
end

return segValidate
