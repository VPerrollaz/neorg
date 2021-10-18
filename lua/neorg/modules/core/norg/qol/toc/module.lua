require("neorg.modules.base")

local module = neorg.modules.create("core.norg.qol.toc")

module.setup = function()
    return { success = true, requires = { "core.integrations.treesitter" } }
end

module.public = {
    --- Find a Table of Contents insertions in the document and returns its data
    --- @return table A table that consist of two values: { item, parameters }.
    --- Parameters can be nil if no parameters to the insertion were given.
    find_toc = function()
        -- Extract any insertion that has a ToC value in it
        local query = vim.treesitter.parse_query(
            "norg",
            [[
                (insertion
                    (insertion_prefix)
                    item: (capitalized_word) @item
                    parameters: (paragraph_segment)? @parameters
                    (#match? @item "^[tT][oO][cC]$")
                )
            ]]
        )

        local exists = false
        local node_data = {
            item = nil,
            parameters = nil,
            line = nil,
        }

        -- The document root is required for iterating over query captures
        local root = module.required["core.integrations.treesitter"].get_document_root()

        if not root then
            return
        end

        -- All captures are looped over here
        for id, node in query:iter_captures(root, 0) do
            -- Extract the name of the capture from the captures table (this makes it easier to perform comparisons on)
            local capture = query.captures[id]

            -- If the capture name is "item" then we set the item variable inside of node_data
            -- It can also optionally be "parameters", in which case that variable will be set too
            node_data[capture] = node

            if node_data.line == nil then
                node_data.line = module.required["core.integrations.treesitter"].get_node_range(node).row_end
            end

            -- This is set to true to tell the program that we've encountered a node
            -- I don't think there's an easier way of doing this, as iter_captures returns a function,
            -- not a list of nodes. We can't simply check if that table of nodes is empty
            exists = true
        end

        if not exists then
            log.error(vim.trim([[
Uh oh! We couldn't generate a Table of Contents because you didn't specify one in the document!
You can do:
    = TOC <Optional custom name for the table of contents>
Anywhere in your document. Doing so will cause the ToC to appear in that location during render.
Type :messages to see full output
            ]]))
            return
        end

        return node_data
    end,

    --- Generates a Table Of Contents (doesn't display it)
    --- @param generator function the function to invoke for each node (used for building the toc)
    --- @return table a table of { text, highlight_group } pairs
    generate_toc = function(toc_data, generator)
        vim.validate({
            toc_data = { toc_data, "table" },
            generator = { generator, "function", true },
        })

        local ts_utils = module.required["core.integrations.treesitter"].get_ts_utils()

        -- Initialize the default generator if it can't be found
        generator = generator
            or function(node, get_text, state)
                local node_type = node:type()

                if vim.startswith(node_type, "heading") and not vim.endswith(node_type, "prefix") then
                    local heading_level = tonumber(node_type:sub(8, 8))

                    return {
                        text = string.rep("*", heading_level) .. " " .. table.concat(
                            ts_utils.get_node_text(node:field("title")[1], 0),
                            " "
                        ),
                        highlight = "NeorgHeading" .. heading_level .. "Title",
                        level = heading_level,
                        state = state,
                    }
                end
            end

        local ts = module.required["core.integrations.treesitter"]

        local result = {
            {
                text = (toc_data.parameters and ts.get_node_text(toc_data.parameters) or "Table of Contents"),
                highlight = "TSAnnotation",
                level = 1,
            },
        }

        local root = module.required["core.integrations.treesitter"].get_document_root()

        if not root then
            return
        end

        local state = {}

        -- Recursively go through all nodes and run the generator on each one
        -- If the generator returns a valid value then store it in the result
        ts.tree_map_rec(function(node)
            local output = generator(node, ts.get_node_text, state)

            if output then
                state = output.state
                table.insert(result, output)
            end
        end)

        return result
    end,

    --- Displays the table of contents to the user
    --- @param left boolean if true will spawn the vertical split on the right hand side
    display_toc = function(left)
        local found_toc = module.public.find_toc()

        if not found_toc then
            return
        end

        local namespace = vim.api.nvim_create_namespace("Neorg ToC")
        local generated_toc = module.public.generate_toc(found_toc)

        if not generated_toc then
            return
        end

        virt_lines = {}
        for i, element in ipairs(generated_toc) do
            table.insert(virt_lines, { { element.text, element.highlight } })
        end

        vim.api.nvim_buf_set_extmark(0, namespace, found_toc.line, 0, { virt_lines = virt_lines })
    end,
}

return module
