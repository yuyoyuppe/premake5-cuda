require("vstudio")

local function writeBoolean(property, value)
  if value == true or value == "On" then
      premake.w('\t<' .. property .. '>true</' .. property .. '>')
  elseif value == false or value == "Off" then
      premake.w('\t<' .. property .. '>false</' .. property .. '>')
  end
end

local function writeString(property, value)
  if value ~= nil and value ~= '' then
      premake.w('\t<' .. property .. '>' .. value .. '</' .. property .. '>')
  end
end

local function writeTableAsOneString(property, values)
  if values ~= nil then
      writeString(property, table.concat(values, ' '))
  end
end

local function hasCudaProjectItems(prj)
  return prj.project.cudaFiles ~= nil or
         prj.project.cudaPTXFiles ~= nil or
         prj.project.cudaLinkFiles ~= nil
end

local function addLinkerProps(cfg)
  local needsStaticLibDeviceLinkOverride =
    cfg.kind == "StaticLib" and
    (cfg.cudaRelocatableCode == true or cfg.cudaRelocatableCode == "On" or
     cfg.cudaExtensibleWholeProgram == true or cfg.cudaExtensibleWholeProgram == "On")

  if cfg.cudaLinkerOptions ~= nil or needsStaticLibDeviceLinkOverride then
      premake.w('<CudaLink>')
      if needsStaticLibDeviceLinkOverride then
        -- Static libraries should archive relocatable device objects; final binaries do device-link.
        writeBoolean('PerformDeviceLink', false)
      end
      writeTableAsOneString('AdditionalOptions', cfg.cudaLinkerOptions)
      premake.w('</CudaLink>')
  end
end

local function writeGlobalString(property, value)
  if value ~= nil and value ~= '' then
      premake.w('<' .. property .. '>' .. value .. '</' .. property .. '>')
  end
end

local function addGlobals(prj)

  -- Set XML tags to their requested values
  writeGlobalString('CudaToolkitCustomDir', prj.cudaPath)

end

local function addCompilerProps(cfg)
  premake.w('<CudaCompile>')

  -- Determine architecture to compile for
  if cfg.architecture == "x86_64" or cfg.architecture == "x64" then
      premake.w('\t<TargetMachinePlatform>64</TargetMachinePlatform>')
  elseif cfg.architecture == "x86" then
      premake.w('\t<TargetMachinePlatform>32</TargetMachinePlatform>')
  else
      error("Unsupported Architecture")
  end

  -- Set XML tags to their requested values
  writeBoolean('Keep', cfg.cudaKeep)
  writeBoolean('GenerateRelocatableDeviceCode', cfg.cudaRelocatableCode)
  writeBoolean('ExtensibleWholeProgramCompilation', cfg.cudaExtensibleWholeProgram)
  writeBoolean('FastMath', cfg.cudaFastMath)
  writeBoolean('PtxAsOptionV', cfg.cudaVerbosePTXAS)
  writeTableAsOneString('AdditionalOptions', cfg.cudaCompilerOptions)
  writeString('MaxRegCount', cfg.cudaMaxRegCount)
  writeString('CudaToolkitCustomDir', cfg.cudaPath)
  writeBoolean('GenerateLineInfo', cfg.cudaGenLineInfo)

  if cfg.cudaIntDir ~= nil and cfg.cudaIntDir ~= '' then
    local e = { }
    e.cfg = cfg
    local v = premake.detoken.expand(cfg.cudaIntDir, e)
    writeString('CompileOut', path.translate(v .. "/%%(Filename)%%(Extension).obj", "\\"))
  end

  if cfg.cudaKeepDir ~= nil and cfg.cudaKeepDir ~= '' then
    local e = { }
    e.cfg = cfg
    local v = premake.detoken.expand(cfg.cudaKeepDir, e)
    writeString('KeepDir', path.translate(v, "\\"))
  end

  -- Code Generation is useless, when you can provide it directly in the compile flags
  premake.w('  <CodeGeneration></CodeGeneration>')
  premake.w('</CudaCompile>')
end

--* Write the CUDA files to be compiled.
local function inlineFileWrite(value)
  local windowsPath = path.translate(path.getabsolute(value), "\\");
  premake.w('\t<CudaCompile ' .. 'Include=' .. string.escapepattern('"') .. windowsPath ..
                string.escapepattern('"') .. '/>')
end

--* Check the glob and match all files.
local function checkForGlob(value)

  --* Absolute paths are easy to parse.
  if (path.isabsolute(value)) then
    local matchingFiles = os.matchfiles(value)
    if matchingFiles ~= null then
      table.foreachi(matchingFiles, inlineFileWrite)
    end
    return
  end

  --* The user probably expects to define relative paths from the project premake5.lua file.
  local projectDir = project().basedir
  local relativeToProjectDir = path.join(projectDir, value)
  local matchingFiles = os.matchfiles(relativeToProjectDir)
  if matchingFiles ~= null then
    table.foreachi(matchingFiles, inlineFileWrite)
  end
end

--* Write the CUDA files to be compiled to PTX.
local function inlineFileWritePTX(value)
  local windowsPath = path.translate(path.getabsolute(value), "\\");
  premake.w('\t<CudaCompile Include=' .. string.escapepattern('"') .. windowsPath ..
                string.escapepattern('"') .. '>')
  premake.w('\t\t<NvccCompilation>ptx</NvccCompilation>')
  premake.w('\t</CudaCompile>')
end

--* Write CUDA device-link inputs. Useful for final binaries linking CUDA static libraries.
local function inlineCudaLinkFileWrite(value, cfg)
  local e = { }
  e.cfg = cfg
  local deviceLinkInput = path.translate(premake.detoken.expand(value, e), "\\")
  premake.w('\t<CudaLink Include=' .. string.escapepattern('"') .. deviceLinkInput ..
                string.escapepattern('"') .. ' ' .. premake.vstudio.vc2010.condition(cfg) .. '>')
  premake.w('\t\t<PerformDeviceLink>true</PerformDeviceLink>')
  premake.w('\t\t<Inputs>' .. deviceLinkInput .. '</Inputs>')
  premake.w('\t</CudaLink>')
end

--* Check the glob and match all files.
local function checkForGlobPTX(value)
  --* Absolute paths are easy to parse.
  if (path.isabsolute(value)) then
    local matchingFiles = os.matchfiles(value)
    if matchingFiles ~= null then
      table.foreachi(matchingFiles, inlineFileWritePTX)
    end
    return
  end

  --* The user probably expects to define relative paths from the project premake5.lua file.
  local projectDir = project().basedir
  local relativeToProjectDir = path.join(projectDir, value)
  local matchingFiles = os.matchfiles(relativeToProjectDir)
  if matchingFiles ~= null then
    table.foreachi(matchingFiles, inlineFileWritePTX)
  end
end

--* Add all CUDA properties enabled by this extension.
local function cudaProjectProps(prj)

  --* All CUDA files will be inside this scope.
  premake.w('<ItemGroup>')

  table.foreachi(prj.project.cudaFiles, checkForGlob)
  table.foreachi(prj.project.cudaPTXFiles, checkForGlobPTX)
  for cfg in premake.project.eachconfig(prj) do
    local cudaLinkFiles = cfg.cudaLinkFiles or prj.project.cudaLinkFiles
    if cudaLinkFiles ~= nil then
      for _, value in ipairs(cudaLinkFiles) do
        inlineCudaLinkFileWrite(value, cfg)
      end
    end
  end

  premake.w('</ItemGroup>')
end

--* Main overriden function. Inserted after CLCompile file list.
premake.override(premake.vstudio.vc2010.elements, "project", function(base, prj)

  local calls = base(prj)

  --* Only enabled if cudaProject defined.
  if hasCudaProjectItems(prj) then
    table.insertafter(calls, premake.vstudio.vc2010.files, cudaProjectProps)
  end

  return calls
end)

--* Add compiler and linker options.
premake.override(premake.vstudio.vc2010.elements, "itemDefinitionGroup", function(oldfn, cfg)
  local items = oldfn(cfg)
  --* Only enabled if cudaProject defined.
  if hasCudaProjectItems(cfg) then
    table.insert(items, addCompilerProps)
    table.insert(items, addLinkerProps)
  end
  return items
end)

--* Add globals
premake.override(premake.vstudio.vc2010.elements, "globals", function(base, prj)
  local calls = base(prj)
  if hasCudaProjectItems(prj) then
    table.insertafter(calls, prj.projectGuid, addGlobals)
  end
  return calls
end)
