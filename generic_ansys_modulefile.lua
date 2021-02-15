-- This file is a symlink target from the module tree.
-- Works for any ANSYS version so longs as the module and install dir are named like previous versions.
-- Finds the first readable (ansyslmd).ini file and sets ANSYSLMD_LICENSE_FILE from it.

local ANSYS = "/opt/nesi/share/ANSYS"
local LICENSES = pathJoin(ANSYS, "Licenses")
local version = myModuleVersion()
local version_code = version:gsub('%.', ''):sub(1,3)

--Gross, must be a nicer way.
if version == "2019R3" then
    version_code = 195
end

if version == "2020R1" then
    version_code = 201
end

if version =="2020R2" then
    version_code = 202
end

local root = pathJoin(ANSYS, 'v' .. version_code)

require 'io'
require 'os'
require 'lfs'
function file_readable(name)
   local f=io.open(name,"r")
   if f~=nil then io.close(f) return true else return false end
end

local license_server = nil
for fn in lfs.dir(LICENSES) do
   if fn:sub(-4) == ".lic" then
      local candidate_licence_file = pathJoin(LICENSES, fn)
      if file_readable(candidate_licence_file) then      
         license_server = capture('source "' .. candidate_licence_file .. '" >/dev/null && echo -n $SERVER')
         setenv('ANSYSLMD_LICENSE_FILE', license_server) --Regular ANSYS
         setenv('ANSOFTD_LICENSE_FILE', license_server) --ANSYS EM
	 --setenv('ANSYSLI_SERVERS', license_server) --ugh
         -- Next line not necessary if LI server is always on default port of same host
         -- setenv('ANSYSLI_SERVERS', capture('source "' .. candidate_licence_file .. '" >/dev/null && echo -n $ANSYSLI_SERVERS'))
         break
      end
   end
end

function ansys_licenses(jobid)
   local tokens = capture("squeue -j " .. jobid .. " --noheader --Format licenses | /bin/awk -F: '/ansys_hpc/ {print $2}'")
   return tonumber(tokens) or 0 
end

function slurm_cpus()
   local tasks = tonumber(os.getenv('SLURM_NTASKS')) or 1
   local threads = tonumber(os.getenv('SLURM_CPUS_PER_TASK')) or 1
   return tasks * threads
end

if mode() == "load" then
   if license_server ~= nil then
      local jobid = os.getenv('SLURM_JOB_ID')
      if jobid ~= nill and license_server == "1055@ansys.licenses.foe.auckland.ac.nz" then
         local tokens = ansys_licenses(jobid)
         local cpus = slurm_cpus()
         if tokens < cpus - 16 then
            LmodMessage("You have requested " .. tostring(tokens) .. " ansys_hpc license tokens for " 
               .. tostring(cpus) .. " CPUs. Please add '#SBATCH --licenses=ansys_hpc:" .. tostring(cpus-16) .. 
               "' (ie: CPUs-16) to ensure there are enough ANSYS HPC licenses available when your job starts.")
         end
      end
   else
      LmodError("You do not appear to be a member of any group licensed to use ANSYS")
   end
end

if not isloaded("libpng/1.2.58") then load("libpng/1.2.58") end
if not isloaded("giflib") then load("giflib") end
conflict("ANSYS")

-- Should be able to use bundled Intel MPI, but mis-matched Perl errors happened when impi not loaded.
-- That is no longer so, but we might still need to set I_MPI_PMI_LIBRARY in case the Slurm module is unloaded.
if version_code == "181" then
   local pmi_module = "impi/2017.6.256-iccifort-2017.6.256-GCC-5.4.0"
   if not isloaded(pmi_module) then
      load(pmi_module)
   end
-- else
--   load("libpmi") 
end

-- Force the use of srun by CFX
setenv('CFX5_START_METHODS_CCL', pathJoin(ANSYS, 'start-methods2.ccl'))
setenv('CFX5_START_METHOD', 'Intel MPI Distributed Parallel')  

-- Force the use of srun by Fluent
setenv("SLURM_ENABLED", "1") 

-- Force the use of srun by Ansys Mechanical and LS-DYNA.
-- This only affects the fake mpirun we add to the ANSYS copies of Intel MPI
setenv("AVOID_IMPI_MPIRUN", "1")

-- Prevent Fluent, LS-DYNA and maybe others from setting CPU affinity because they get it wrong.
setenv("FLUENT_AFFINITY", "0")
setenv("LD_PRELOAD", pathJoin(ANSYS, "affxcept.so"))

prepend_path("LD_LIBRARY_PATH", pathJoin(root, "Tools/mono/Linux64/lib/"))

prepend_path("PATH", pathJoin(root, "tgrid/bin"))
prepend_path("PATH", pathJoin(root, "Framework/bin/Linux64"))
prepend_path("PATH", pathJoin(root, "aisol/bin/linx64"))
prepend_path("PATH", pathJoin(root, "RSM/bin"))
prepend_path("PATH", pathJoin(root, "ansys/bin"))
prepend_path("PATH", pathJoin(root, "autodyn/bin"))
prepend_path("PATH", pathJoin(root, "CFD-Post/bin"))
prepend_path("PATH", pathJoin(root, "CFX/bin"))
prepend_path("PATH", pathJoin(root, "fluent/bin"))
prepend_path("PATH", pathJoin(root, "TurboGrid/bin"))
prepend_path("PATH", pathJoin(root, "polyflow/bin"))
prepend_path("PATH", pathJoin(root, "Icepak/bin"))
prepend_path("PATH", pathJoin(root, "icemcfd/linux64_amd/bin"))
prepend_path("PATH", pathJoin(root, "fensapice/bin"))
prepend_path("PATH", pathJoin(root, "AnsysEM/Linux64"))
prepend_path("PATH", pathJoin(root, "Electronics/Linux64"))
prepend_path("PATH", pathJoin(root, "SystemCoupling/bin"))
prepend_path("PATH", pathJoin(ANSYS, "shared_files/licensing/linx64"))   -- for lmutil etc.
prepend_path("PATH", pathJoin(ANSYS, "nesi_bin"))   -- for custom functions.
prepend_path("PATH", ANSYS)


setenv("FLUENT_INC", pathJoin(root, "fluent"))  -- Zendesk #21262
setenv("FLUENT_ARCH", "lnamd64")

setenv("ICEM_ACN", pathJoin(root,  "icemcfd/linux64_amd"))
setenv("WORKBENCH_CMD", "srun -N1 -n1 " .. pathJoin(root,  "aisol/.workbench") .. " -cmd ")

setenv("ANSYSLI_MSGS_DIR", pathJoin(ANSYS, "shared_files/licensing/language/en-us"))
setenv("ARC_MONO_DIR", pathJoin(root, "AnsysEM/Linux64/common/mono/Linux64"))
setenv("MWHOME", pathJoin(root, "AnsysEM/Linux64/mainwin540/"))
setenv("ANS_NODEPCHECK", "1")

-- setenv("AWPBROOT

-- setenv("ANSYS_ROOT" .. version_code, root)

-- No point in these aliases unless they work in scripts, but expand_aliases defaults to off in non-interactive bash.
-- set_alias('srun-fluent', 'fluent -slurm -t$SLURM_NTASKS')
-- set_alias('srun-cfx5solve', 'cfx5solve -part $SLURM_NTASKS')
-- set_alias('srun-lsdyna', 'lsdyna' .. ' memory=$(($SLURM_MEM_PER_CPU/8))M -dis -np $SLURM_NTASKS')

set_alias('prefer_teaching_license', 'ansysli_util -revn ' .. version_code .. ' -saveuserprefs ' .. pathJoin(ANSYS, 'prefer_teaching_license.xml'))
set_alias('prefer_research_license', 'ansysli_util -revn ' .. version_code .. ' -saveuserprefs ' .. pathJoin(ANSYS, 'prefer_research_license.xml'))
set_alias('fensap2slurm', 'python ' .. pathJoin(root, 'fensapice/fensap2slurm/fensap2slurm.py'))


whatis([[Description: A bundle of computer-aided engineering software including Fluent and CFX - Homepage: http://www.ansys.com]])

