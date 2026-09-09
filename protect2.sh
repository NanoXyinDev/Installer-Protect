#!/usr/bin/env bash
set -euo pipefail

#!/usr/bin/env bash
set -euo pipefail

ACCESS_KEY="ZxvHost"
PANEL_DIR="${PANEL_DIR:-/var/www/pterodactyl}"
BACKUP_ROOT="/var/backups/zxv-official-protect"
STATE_FILE="/var/lib/zxv-official-protect/state"
SELF_UNINSTALL="/usr/local/sbin/uninstall-zxv-protect.sh"

NC='\033[0m'; CYAN='\033[1;36m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'; RED='\033[1;31m'; MAGENTA='\033[1;35m'
info(){ printf "${CYAN}[@]${NC} %s\n" "$1"; }
ok(){ printf "${GREEN}[+]${NC} %s\n" "$1"; }
warn(){ printf "${YELLOW}[!]${NC} %s\n" "$1"; }
die(){ printf "${RED}[-]${NC} %s\n" "$1"; exit 1; }

banner(){
clear
printf "${MAGENTA}"
cat <<'ASCII'
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@                                                      @
@              Z X V   O F F I C I A L                 @
@                P R O T E C T                         @
@                                                      @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
ASCII
printf "${NC}\n"
}

resolve_target(){
  local p="$1"
  case "$p" in
    /var/www/pterodactyl/*) printf '%s%s\n' "$PANEL_DIR" "${p#/var/www/pterodactyl}" ;;
    *) printf '%s\n' "$p" ;;
  esac
}

need_root(){ [[ $EUID -eq 0 ]] || die "Jalankan sebagai root."; }
check_panel(){ [[ -d "$PANEL_DIR" && -f "$PANEL_DIR/artisan" ]] || die "Pterodactyl tidak ditemukan di: $PANEL_DIR"; }

make_backup(){
  local target="$1"
  mkdir -p "$BACKUP_DIR"
  if [[ -e "$target" ]]; then
    local rel="${target#/}"
    mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
    cp -a "$target" "$BACKUP_DIR/$rel"
    printf 'EXIST|%s|%s\n' "$target" "$BACKUP_DIR/$rel" >> "$MANIFEST"
  else
    printf 'NEW|%s|\n' "$target" >> "$MANIFEST"
  fi
}

install_file(){
  local target="$1"
  local tmp
  tmp="$(mktemp)"
  cat > "$tmp"
  mkdir -p "$(dirname "$target")"
  make_backup "$target"
  install -m 0644 "$tmp" "$target"
  rm -f "$tmp"
  ok "Installed: ${target#$PANEL_DIR/}"
}

prepare(){
  need_root
  check_panel
  mkdir -p "$BACKUP_ROOT" "$(dirname "$STATE_FILE")" /usr/local/sbin
  BACKUP_DIR="$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$BACKUP_DIR"
  MANIFEST="$BACKUP_DIR/manifest"
  : > "$MANIFEST"
  printf '%s\n' "$BACKUP_DIR" > "$STATE_FILE"
  write_uninstaller
  info "Backup: $BACKUP_DIR"
}

post_install(){
  if command -v php >/dev/null 2>&1 && [[ -f "$PANEL_DIR/artisan" ]]; then
    php -l "$PANEL_DIR/app/Http/Controllers/Admin/Servers/ServerController.php" >/dev/null && ok "PHP syntax check: OK"
    (cd "$PANEL_DIR" && php artisan optimize:clear >/dev/null 2>&1) && ok "Laravel cache: cleared" || warn "Laravel cache clear dilewati."
  fi
  ok "Protection selesai."
}

write_uninstaller(){
cat > "$SELF_UNINSTALL" <<'UNINSTALL'
#!/usr/bin/env bash
set -euo pipefail
STATE_FILE="/var/lib/zxv-official-protect/state"
NC='\033[0m'; GREEN='\033[1;32m'; RED='\033[1;31m'; CYAN='\033[1;36m'
[[ $EUID -eq 0 ]] || { printf "${RED}[-]${NC} Root diperlukan.\n"; exit 1; }
[[ -f "$STATE_FILE" ]] || { printf "${RED}[-]${NC} Tidak ada state backup ZXV OFFICIAL.\n"; exit 1; }
BACKUP_DIR="$(cat "$STATE_FILE")"
MANIFEST="$BACKUP_DIR/manifest"
[[ -f "$MANIFEST" ]] || { printf "${RED}[-]${NC} Manifest backup tidak ditemukan.\n"; exit 1; }
printf "${CYAN}[@]${NC} Restore: %s\n" "$BACKUP_DIR"
while IFS='|' read -r kind target backup; do
  [[ -n "$target" ]] || continue
  if [[ "$kind" == "EXIST" ]]; then
    mkdir -p "$(dirname "$target")"
    cp -a "$backup" "$target"
    printf "${GREEN}[+]${NC} Restored: %s\n" "$target"
  elif [[ "$kind" == "NEW" ]]; then
    rm -f "$target"
    printf "${GREEN}[+]${NC} Removed: %s\n" "$target"
  fi
done < "$MANIFEST"
rm -f "$STATE_FILE"
if [[ -f "/var/www/pterodactyl/artisan" ]] && command -v php >/dev/null 2>&1; then
  (cd /var/www/pterodactyl && php artisan optimize:clear >/dev/null 2>&1) || true
fi
printf "${GREEN}[+]${NC} ZXV OFFICIAL Protect berhasil di-uninstall.\n"
UNINSTALL
chmod +x "$SELF_UNINSTALL"
}

install_indices(){
  local -a idx=("$@")
  local i path code target
  if [[ " ${SELECTED[*]} " == *" 1 "* ]]; then
    target="$(resolve_target '/var/www/pterodactyl/app/Http/Controllers/Admin/Servers/ServerController.php')"
    install_file "$target" <<'ZXV_FILE_1'
<?php

namespace Pterodactyl\Http\Controllers\Admin\Servers;

use Illuminate\View\View;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Pterodactyl\Models\Server;
use Pterodactyl\Models\User;
use Pterodactyl\Models\Nest;
use Pterodactyl\Models\Location;
use Spatie\QueryBuilder\QueryBuilder;
use Spatie\QueryBuilder\AllowedFilter;
use Pterodactyl\Http\Controllers\Controller;
use Pterodactyl\Models\Filters\AdminServerFilter;
use Illuminate\Contracts\View\Factory as ViewFactory;

class ServerController extends Controller
{
    /**
     * Konstruktor
     */
    public function __construct(private ViewFactory $view)
    {
    }

/**
 * 📋 Daftar server — hanya tampilkan milik sendiri kecuali admin ID 1
 */
public function index(Request $request): View
{
    $user = Auth::user();

    // Ambil query dasar
$query = Server::query()
    ->with(['node', 'user', 'allocation'])
    ->orderBy('id', 'asc'); // server baru di bawah

    // NDyProtect v1.5 — Batasi query utama
    if ($user->id !== 1) {
        $query->where('owner_id', $user->id);
    }

    // Gunakan QueryBuilder tapi tetap batasi hasil user
    $servers = QueryBuilder::for($query)
        ->allowedFilters([
            AllowedFilter::exact('owner_id'),
            AllowedFilter::custom('*', new AdminServerFilter()),
        ])
        ->when($request->has('filter') && isset($request->filter['search']), function ($q) use ($request) {
            $search = $request->filter['search'];
            $q->where(function ($sub) use ($search) {
                $sub->where('name', 'like', "%{$search}%")
                    ->orWhere('uuidShort', 'like', "%{$search}%")
                    ->orWhere('uuid', 'like', "%{$search}%");
            });
        })
        ->paginate(config('pterodactyl.paginate.admin.servers'))
        ->appends($request->query());

    return $this->view->make('admin.servers.index', ['servers' => $servers]);
}

    /**
     * 🧱 Form buat server baru
     */
    public function create(): View
    {
        $user = Auth::user();

        if ($user->id === 1) {
            // Admin ID 1 bisa pilih owner siapa pun
            $users = User::all();
            $lock_owner = false;
            $auto_owner = null;
        } else {
            // User biasa hanya bisa membuat server untuk dirinya sendiri
            $users = collect([$user]);
            $lock_owner = true;
            $auto_owner = $user;
        }

        return $this->view->make('admin.servers.new', [
            'users' => $users,
            'lock_owner' => $lock_owner,
            'auto_owner' => $auto_owner,
            'locations' => Location::with('nodes')->get(),
            'nests' => Nest::with('eggs')->get(),
        ]);
    }

    /**
     * 🔍 Detail/Edit Server — hanya pemilik server atau admin ID 1
     */
    public function view(Server $server): View
    {
        $user = Auth::user();

        // 🔐 ZXV OFFICIAL — Server ID 1 adalah halaman khusus Admin Utama.
        if ((int) $server->id === 1 && (!$user || (int) $user->id !== 1)) {
            return $this->view->make('admin.owner-only');
        }

        if (!$user || ($user->id !== 1 && $server->owner_id !== $user->id)) {
            abort(403, '🚫 Akses ditolak: Hanya admin ID 1 yang dapat melihat atau mengedit server ini! ©ZXV OFFICIAL');
        }

        return $this->view->make('admin.servers.view', ['server' => $server]);
    }

    /**
     * 🛠 Update Server — hanya pemilik server atau admin ID 1
     */
    public function update(Request $request, Server $server)
    {
        $user = Auth::user();

        if ($user->id !== 1 && $server->owner_id !== $user->id) {
            abort(403, '🚫 Akses ditolak: Hanya admin ID 1 yang dapat mengubah server ini! ©ZXV OFFICIAL — XyrooXellz.');
        }

        // Lindungi agar user biasa tidak bisa ubah owner_id
        $data = $request->except(['owner_id']);

        $server->update($data);

        return redirect()->route('admin.servers.view', $server->id)
            ->with('success', '✅ Server berhasil diperbarui.');
    }

    /**
     * ❌ Hapus Server — hanya Admin ID 1
     */
    public function destroy(Server $server)
    {
        $user = Auth::user();

        if ($user->id !== 1) {
            abort(403, '🚫 Akses ditolak: Hanya admin ID 1 yang dapat menghapus server ini! ©ZXV OFFICIAL — XyrooXellz.');
        }

        $server->delete();

        return redirect()->route('admin.servers')
            ->with('success', '🗑️ Server berhasil dihapus.');
    }
}
ZXV_FILE_1
  fi

  if [[ " ${SELECTED[*]} " == *" 2 "* ]]; then
    target="$(resolve_target '/var/www/pterodactyl/resources/views/admin/owner-only.blade.php')"
    install_file "$target" <<'ZXV_FILE_2'
<!DOCTYPE html>
<html lang="id">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>ADMIN UTAMA | KHUSUS ADMIN UTAMA</title>
    <style>
        :root { color-scheme: dark; }
        * { box-sizing: border-box; }
        body { margin:0; min-height:100vh; display:grid; place-items:center; padding:24px; font-family:Arial,sans-serif; background:#0b1220; color:#e8eefc; }
        .card { width:min(560px,100%); padding:36px 28px; text-align:center; border:1px solid #263957; border-radius:22px; background:linear-gradient(145deg,#101a2c,#0d1524); box-shadow:0 20px 60px rgba(0,0,0,.45); }
        .icon { font-size:52px; margin-bottom:14px; }
        h1 { margin:0 0 12px; font-size:clamp(28px,7vw,44px); }
        .badge { display:inline-block; margin:18px 0 6px; padding:9px 14px; border-radius:999px; background:rgba(53,208,255,.12); border:1px solid rgba(53,208,255,.35); color:#76defc; font-weight:700; }
        p { margin:8px 0; color:#aebbd0; line-height:1.6; }
        .brand { margin-top:24px; color:#8090aa; font-size:13px; }
        .brand strong { color:#fff; }
    </style>
</head>
<body>
    <main class="card" role="main" aria-labelledby="title">
        <div class="icon">🔒</div>
        <h1 id="title">ADMIN UTAMA</h1>
        <div class="badge">KHUSUS ADMIN UTAMA</div>
        <p>Halaman <strong>/view/1</strong> dikunci dan hanya dapat dibuka oleh akun Admin Utama.</p>
        <p>Akses kamu ke halaman ini telah dibatasi.</p>
        <div class="brand">Protected by <strong>ZXV OFFICIAL</strong></div>
    </main>
</body>
</html>
ZXV_FILE_2
  fi

  if [[ " ${SELECTED[*]} " == *" 3 "* ]]; then
    target="$(resolve_target '/var/www/pterodactyl/resources/views/admin/servers/new.blade.php')"
    install_file "$target" <<'ZXV_FILE_3'
@extends('layouts.admin')

@section('title')
    New Server
@endsection

@section('content-header')
    <h1>Create Server<small>Add a new server to the panel.</small></h1>
    <ol class="breadcrumb">
        <li><a href="{{ route('admin.index') }}">Admin</a></li>
        <li><a href="{{ route('admin.servers') }}">Servers</a></li>
        <li class="active">Create Server</li>
    </ol>
@endsection

@section('content')
<form action="{{ route('admin.servers.new') }}" method="POST">
    <div class="row">
        <div class="col-xs-12">
            <div class="box">
                <div class="box-header with-border">
                    <h3 class="box-title">Core Details</h3>
                </div>

                <div class="box-body row">
                    <div class="col-md-6">
                        <div class="form-group">
                            <label for="pName">Server Name</label>
                            <input type="text" class="form-control" id="pName" name="name" value="{{ old('name') }}" placeholder="Server Name">
                            <p class="small text-muted no-margin">Character limits: <code>a-z A-Z 0-9 _ - .</code> and <code>[Space]</code>.</p>
                        </div>

<div class="form-group">
    <label for="pUserId">Server Owner</label>

    @if(Auth::user()->id == 1)
        {{-- Admin ID 1: bisa isi manual --}}
        <select id="pUserId" name="owner_id" class="form-control">
            <option value="">Select a User</option>
            @foreach(\Pterodactyl\Models\User::all() as $user)
                <option value="{{ $user->id }}" @selected(old('owner_id') == $user->id)>
                    {{ $user->username }} ({{ $user->email }})
                </option>
            @endforeach
        </select>
        <p class="small text-muted no-margin">As admin, you can manually choose the server owner.</p>
    @else
        {{-- Selain admin ID 1: otomatis --}}
        <input type="hidden" id="pUserId" name="owner_id" value="{{ Auth::user()->id }}">
        <input type="text" class="form-control" value="{{ Auth::user()->email }}" disabled>
        <p class="small text-muted no-margin">This server will be owned by your account automatically.</p>
    @endif
</div>
                    </div>

                    <div class="col-md-6">
                        <div class="form-group">
                            <label for="pDescription" class="control-label">Server Description</label>
                            <textarea id="pDescription" name="description" rows="3" class="form-control">{{ old('description') }}</textarea>
                            <p class="text-muted small">A brief description of this server.</p>
                        </div>

                        <div class="form-group">
                            <div class="checkbox checkbox-primary no-margin-bottom">
                                <input id="pStartOnCreation" name="start_on_completion" type="checkbox" {{ \Pterodactyl\Helpers\Utilities::checked('start_on_completion', 1) }} />
                                <label for="pStartOnCreation" class="strong">Start Server when Installed</label>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <div class="row">
        <div class="col-xs-12">
            <div class="box">
                <div class="overlay" id="allocationLoader" style="display:none;"><i class="fa fa-refresh fa-spin"></i></div>
                <div class="box-header with-border">
                    <h3 class="box-title">Allocation Management</h3>
                </div>

                <div class="box-body row">
                    <div class="form-group col-sm-4">
                        <label for="pNodeId">Node</label>
                        <select name="node_id" id="pNodeId" class="form-control">
                            @foreach($locations as $location)
                                <optgroup label="{{ $location->long }} ({{ $location->short }})">
                                @foreach($location->nodes as $node)

                                <option value="{{ $node->id }}"
                                    @if($location->id === old('location_id')) selected @endif
                                >{{ $node->name }}</option>

                                @endforeach
                                </optgroup>
                            @endforeach
                        </select>

                        <p class="small text-muted no-margin">The node which this server will be deployed to.</p>
                    </div>

                    <div class="form-group col-sm-4">
                        <label for="pAllocation">Default Allocation</label>
                        <select id="pAllocation" name="allocation_id" class="form-control"></select>
                        <p class="small text-muted no-margin">The main allocation that will be assigned to this server.</p>
                    </div>

                    <div class="form-group col-sm-4">
                        <label for="pAllocationAdditional">Additional Allocation(s)</label>
                        <select id="pAllocationAdditional" name="allocation_additional[]" class="form-control" multiple></select>
                        <p class="small text-muted no-margin">Additional allocations to assign to this server on creation.</p>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <div class="row">
        <div class="col-xs-12">
            <div class="box">
                <div class="overlay" id="allocationLoader" style="display:none;"><i class="fa fa-refresh fa-spin"></i></div>
                <div class="box-header with-border">
                    <h3 class="box-title">Application Feature Limits</h3>
                </div>

                <div class="box-body row">
                    <div class="form-group col-xs-6">
                        <label for="pDatabaseLimit" class="control-label">Database Limit</label>
                        <div>
                            <input type="text" id="pDatabaseLimit" name="database_limit" class="form-control" value="{{ old('database_limit', 0) }}"/>
                        </div>
                        <p class="text-muted small">The total number of databases a user is allowed to create for this server.</p>
                    </div>
                    <div class="form-group col-xs-6">
                        <label for="pAllocationLimit" class="control-label">Allocation Limit</label>
                        <div>
                            <input type="text" id="pAllocationLimit" name="allocation_limit" class="form-control" value="{{ old('allocation_limit', 0) }}"/>
                        </div>
                        <p class="text-muted small">The total number of allocations a user is allowed to create for this server.</p>
                    </div>
                    <div class="form-group col-xs-6">
                        <label for="pBackupLimit" class="control-label">Backup Limit</label>
                        <div>
                            <input type="text" id="pBackupLimit" name="backup_limit" class="form-control" value="{{ old('backup_limit', 0) }}"/>
                        </div>
                        <p class="text-muted small">The total number of backups that can be created for this server.</p>
                    </div>
                </div>
            </div>
        </div>
    </div>
    <div class="row">
        <div class="col-xs-12">
            <div class="box">
                <div class="box-header with-border">
                    <h3 class="box-title">Resource Management</h3>
                </div>

                <div class="box-body row">
                    <div class="form-group col-xs-6">
                        <label for="pCPU">CPU Limit</label>

                        <div class="input-group">
                            <input type="text" id="pCPU" name="cpu" class="form-control" value="{{ old('cpu', 0) }}" />
                            <span class="input-group-addon">%</span>
                        </div>

                        <p class="text-muted small">If you do not want to limit CPU usage, set the value to <code>0</code>. To determine a value, take the number of threads and multiply it by 100. For example, on a quad core system without hyperthreading <code>(4 * 100 = 400)</code> there is <code>400%</code> available. To limit a server to using half of a single thread, you would set the value to <code>50</code>. To allow a server to use up to two threads, set the value to <code>200</code>.<p>
                    </div>

                    <div class="form-group col-xs-6">
                        <label for="pThreads">CPU Pinning</label>

                        <div>
                            <input type="text" id="pThreads" name="threads" class="form-control" value="{{ old('threads') }}" />
                        </div>

                        <p class="text-muted small"><strong>Advanced:</strong> Enter the specific CPU threads that this process can run on, or leave blank to allow all threads. This can be a single number, or a comma separated list. Example: <code>0</code>, <code>0-1,3</code>, or <code>0,1,3,4</code>.</p>
                    </div>
                </div>

                <div class="box-body row">
                    <div class="form-group col-xs-6">
                        <label for="pMemory">Memory</label>

                        <div class="input-group">
                            <input type="text" id="pMemory" name="memory" class="form-control" value="{{ old('memory') }}" />
                            <span class="input-group-addon">MiB</span>
                        </div>

                        <p class="text-muted small">The maximum amount of memory allowed for this container. Setting this to <code>0</code> will allow unlimited memory in a container.</p>
                    </div>

                    <div class="form-group col-xs-6">
                        <label for="pSwap">Swap</label>

                        <div class="input-group">
                            <input type="text" id="pSwap" name="swap" class="form-control" value="{{ old('swap', 0) }}" />
                            <span class="input-group-addon">MiB</span>
                        </div>

                        <p class="text-muted small">Setting this to <code>0</code> will disable swap space on this server. Setting to <code>-1</code> will allow unlimited swap.</p>
                    </div>
                </div>

                <div class="box-body row">
                    <div class="form-group col-xs-6">
                        <label for="pDisk">Disk Space</label>

                        <div class="input-group">
                            <input type="text" id="pDisk" name="disk" class="form-control" value="{{ old('disk') }}" />
                            <span class="input-group-addon">MiB</span>
                        </div>

                        <p class="text-muted small">This server will not be allowed to boot if it is using more than this amount of space. If a server goes over this limit while running it will be safely stopped and locked until enough space is available. Set to <code>0</code> to allow unlimited disk usage.</p>
                    </div>

                    <div class="form-group col-xs-6">
                        <label for="pIO">Block IO Weight</label>

                        <div>
                            <input type="text" id="pIO" name="io" class="form-control" value="{{ old('io', 500) }}" />
                        </div>

                        <p class="text-muted small"><strong>Advanced</strong>: The IO performance of this server relative to other <em>running</em> containers on the system. Value should be between <code>10</code> and <code>1000</code>. Please see <a href="https://docs.docker.com/engine/reference/run/#block-io-bandwidth-blkio-constraint" target="_blank">this documentation</a> for more information about it.</p>
                    </div>
                    <div class="form-group col-xs-12">
                        <div class="checkbox checkbox-primary no-margin-bottom">
                            <input type="checkbox" id="pOomDisabled" name="oom_disabled" value="0" {{ \Pterodactyl\Helpers\Utilities::checked('oom_disabled', 0) }} />
                            <label for="pOomDisabled" class="strong">Enable OOM Killer</label>
                        </div>

                        <p class="small text-muted no-margin">Terminates the server if it breaches the memory limits. Enabling OOM killer may cause server processes to exit unexpectedly.</p>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <div class="row">
        <div class="col-md-6">
            <div class="box">
                <div class="box-header with-border">
                    <h3 class="box-title">Nest Configuration</h3>
                </div>

                <div class="box-body row">
                    <div class="form-group col-xs-12">
                        <label for="pNestId">Nest</label>

                        <select id="pNestId" name="nest_id" class="form-control">
                            @foreach($nests as $nest)
                                <option value="{{ $nest->id }}"
                                    @if($nest->id === old('nest_id'))
                                        selected="selected"
                                    @endif
                                >{{ $nest->name }}</option>
                            @endforeach
                        </select>

                        <p class="small text-muted no-margin">Select the Nest that this server will be grouped under.</p>
                    </div>

                    <div class="form-group col-xs-12">
                        <label for="pEggId">Egg</label>
                        <select id="pEggId" name="egg_id" class="form-control"></select>
                        <p class="small text-muted no-margin">Select the Egg that will define how this server should operate.</p>
                    </div>
                    <div class="form-group col-xs-12">
                        <div class="checkbox checkbox-primary no-margin-bottom">
                            <input type="checkbox" id="pSkipScripting" name="skip_scripts" value="1" {{ \Pterodactyl\Helpers\Utilities::checked('skip_scripts', 0) }} />
                            <label for="pSkipScripting" class="strong">Skip Egg Install Script</label>
                        </div>

                        <p class="small text-muted no-margin">If the selected Egg has an install script attached to it, the script will run during the install. If you would like to skip this step, check this box.</p>
                    </div>
                </div>
            </div>
        </div>

        <div class="col-md-6">
            <div class="box">
                <div class="box-header with-border">
                    <h3 class="box-title">Docker Configuration</h3>
                </div>

                <div class="box-body row">
                    <div class="form-group col-xs-12">
                        <label for="pDefaultContainer">Docker Image</label>
                        <select id="pDefaultContainer" name="image" class="form-control"></select>
                        <input id="pDefaultContainerCustom" name="custom_image" value="{{ old('custom_image') }}" class="form-control" placeholder="Or enter a custom image..." style="margin-top:1rem"/>
                        <p class="small text-muted no-margin">This is the default Docker image that will be used to run this server. Select an image from the dropdown above, or enter a custom image in the text field above.</p>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <div class="row">
        <div class="col-md-12">
            <div class="box">
                <div class="box-header with-border">
                    <h3 class="box-title">Startup Configuration</h3>
                </div>

                <div class="box-body row">
                    <div class="form-group col-xs-12">
                        <label for="pStartup">Startup Command</label>
                        <input type="text" id="pStartup" name="startup" value="{{ old('startup') }}" class="form-control" />
                        <p class="small text-muted no-margin">The following data substitutes are available for the startup command: <code>@{{SERVER_MEMORY}}</code>, <code>@{{SERVER_IP}}</code>, and <code>@{{SERVER_PORT}}</code>. They will be replaced with the allocated memory, server IP, and server port respectively.</p>
                    </div>
                </div>

                <div class="box-header with-border" style="margin-top:-10px;">
                    <h3 class="box-title">Service Variables</h3>
                </div>

                <div class="box-body row" id="appendVariablesTo"></div>

                <div class="box-footer">
                    {!! csrf_field() !!}
                    <input type="submit" class="btn btn-success pull-right" value="Create Server" />
                </div>
            </div>
        </div>
    </div>
</form>
@endsection

@section('footer-scripts')
    @parent
    {!! Theme::js('vendor/lodash/lodash.js') !!}

    <script type="application/javascript">
        // Persist 'Service Variables'
        function serviceVariablesUpdated(eggId, ids) {
            @if (old('egg_id'))
                // Check if the egg id matches.
                if (eggId != '{{ old('egg_id') }}') {
                    return;
                }

                @if (old('environment'))
                    @foreach (old('environment') as $key => $value)
                        $('#' + ids['{{ $key }}']).val('{{ $value }}');
                    @endforeach
                @endif
            @endif
            @if(old('image'))
                $('#pDefaultContainer').val('{{ old('image') }}');
            @endif
        }
        // END Persist 'Service Variables'
    </script>

    {!! Theme::js('js/admin/new-server.js?v=20220530') !!}

    <script type="application/javascript">
        $(document).ready(function() {
// Persist 'Server Owner' select2
// (Removed because Server Owner now auto-fills based on logged-in user)
// END Persist 'Server Owner' select2

            // Persist 'Node' select2
            @if (old('node_id'))
                $('#pNodeId').val('{{ old('node_id') }}').change();

                // Persist 'Default Allocation' select2
                @if (old('allocation_id'))
                    $('#pAllocation').val('{{ old('allocation_id') }}').change();
                @endif
                // END Persist 'Default Allocation' select2

                // Persist 'Additional Allocations' select2
                @if (old('allocation_additional'))
                    const additional_allocations = [];

                    @for ($i = 0; $i < count(old('allocation_additional')); $i++)
                        additional_allocations.push('{{ old('allocation_additional.'.$i)}}');
                    @endfor

                    $('#pAllocationAdditional').val(additional_allocations).change();
                @endif
                // END Persist 'Additional Allocations' select2
            @endif
            // END Persist 'Node' select2

            // Persist 'Nest' select2
            @if (old('nest_id'))
                $('#pNestId').val('{{ old('nest_id') }}').change();

                // Persist 'Egg' select2
                @if (old('egg_id'))
                    $('#pEggId').val('{{ old('egg_id') }}').change();
                @endif
                // END Persist 'Egg' select2
            @endif
            // END Persist 'Nest' select2
        });
    </script>
@endsection

ZXV_FILE_3
  fi

  if [[ " ${SELECTED[*]} " == *" 4 "* ]]; then
    target="$(resolve_target '/var/www/pterodactyl/app/Services/Servers/DetailsModificationService.php')"
    install_file "$target" <<'ZXV_FILE_4'
<?php

namespace Pterodactyl\Services\Servers;

use Illuminate\Support\Arr;
use Illuminate\Support\Facades\Auth;
use Pterodactyl\Models\Server;
use Illuminate\Database\ConnectionInterface;
use Pterodactyl\Traits\Services\ReturnsUpdatedModels;
use Pterodactyl\Repositories\Wings\DaemonServerRepository;
use Pterodactyl\Exceptions\DisplayException;
use Pterodactyl\Exceptions\Http\Connection\DaemonConnectionException;

class DetailsModificationService
{
    use ReturnsUpdatedModels;

    public function __construct(
        private ConnectionInterface $connection,
        private DaemonServerRepository $serverRepository
    ) {
    }

    /**
     * 🧱 NDyProtect v1.1 — Anti Edit Server
     * Mencegah user non-admin mengubah detail server milik orang lain.
     */
    public function handle(Server $server, array $data): Server
    {
        $user = Auth::user();

        // Proteksi: hanya Admin ID 1 boleh ubah detail server orang lain
        if ($user && $user->id !== 1) {
            $ownerId = $server->owner_id ?? $server->user_id ?? null;

            if ($ownerId !== $user->id) {
                throw new DisplayException(
                    '🚫 Akses ditolak: Hanya Admin ID 1 yang dapat mengubah detail server milik orang lain! ©ZXV OFFICIAL — XyrooXellz'
                );
            }
        }

        // Jalankan proses bawaan
        return $this->connection->transaction(function () use ($data, $server) {
            $owner = $server->owner_id;

            $server->forceFill([
                'external_id' => Arr::get($data, 'external_id'),
                'owner_id' => Arr::get($data, 'owner_id'),
                'name' => Arr::get($data, 'name'),
                'description' => Arr::get($data, 'description') ?? '',
            ])->saveOrFail();

            // Jika owner diganti, cabut akses owner lama di Wings
            if ($server->owner_id !== $owner) {
                try {
                    $this->serverRepository->setServer($server)->revokeUserJTI($owner);
                } catch (DaemonConnectionException $exception) {
                    // Abaikan error jika Wings sedang offline
                }
            }

            return $server;
        });
    }
}
ZXV_FILE_4
  fi

  if [[ " ${SELECTED[*]} " == *" 5 "* ]]; then
    target="$(resolve_target '/var/www/pterodactyl/app/Services/Servers/BuildModificationService.php')"
    install_file "$target" <<'ZXV_FILE_5'
<?php

namespace Pterodactyl\Services\Servers;

use Illuminate\Support\Arr;
use Pterodactyl\Models\Server;
use Pterodactyl\Models\Allocation;
use Illuminate\Support\Facades\Log;
use Illuminate\Database\ConnectionInterface;
use Pterodactyl\Exceptions\DisplayException;
use Illuminate\Support\Facades\Auth;
use Illuminate\Database\Eloquent\ModelNotFoundException;
use Pterodactyl\Repositories\Wings\DaemonServerRepository;
use Pterodactyl\Exceptions\Http\Connection\DaemonConnectionException;

class BuildModificationService
{
    public function __construct(
        private ConnectionInterface $connection,
        private DaemonServerRepository $daemonServerRepository,
        private ServerConfigurationStructureService $structureService
    ) {
    }

    /**
     * 🧱 NDyProtect v1.1 — Anti Build Abuse
     * Mencegah user non-admin mengubah konfigurasi Build server milik orang lain.
     *
     * @throws \Throwable
     * @throws \Pterodactyl\Exceptions\DisplayException
     */
    public function handle(Server $server, array $data): Server
    {
        $user = Auth::user();

        // NDyProtect — Cegah user biasa ubah konfigurasi server yang bukan miliknya
        if ($user && $user->id !== 1) {
            $ownerId = $server->owner_id ?? $server->user_id ?? null;

            if ($ownerId !== $user->id) {
                throw new DisplayException(
                    '🚫 Akses ditolak: Hanya Admin ID 1 yang dapat mengubah Build Configuration server orang lain! ©ZXV OFFICIAL — XyrooXellz'
                );
            }
        }

        // Jalankan proses asli (tetap sama dengan bawaan Pterodactyl)
        /** @var \Pterodactyl\Models\Server $server */
        $server = $this->connection->transaction(function () use ($server, $data) {
            $this->processAllocations($server, $data);

            if (isset($data['allocation_id']) && $data['allocation_id'] != $server->allocation_id) {
                try {
                    Allocation::query()
                        ->where('id', $data['allocation_id'])
                        ->where('server_id', $server->id)
                        ->firstOrFail();
                } catch (ModelNotFoundException) {
                    throw new DisplayException('The requested default allocation is not currently assigned to this server.');
                }
            }

            $merge = Arr::only($data, [
                'oom_disabled',
                'memory',
                'swap',
                'io',
                'cpu',
                'threads',
                'disk',
                'allocation_id',
            ]);

            $server->forceFill(array_merge($merge, [
                'database_limit' => Arr::get($data, 'database_limit', 0) ?? null,
                'allocation_limit' => Arr::get($data, 'allocation_limit', 0) ?? null,
                'backup_limit' => Arr::get($data, 'backup_limit', 0) ?? 0,
            ]))->saveOrFail();

            return $server->refresh();
        });

        $updateData = $this->structureService->handle($server);

        if (!empty($updateData['build'])) {
            try {
                $this->daemonServerRepository->setServer($server)->sync();
            } catch (DaemonConnectionException $exception) {
                Log::warning($exception, ['server_id' => $server->id]);
            }
        }

        return $server;
    }

    /**
     * Proses alokasi (port) untuk server.
     */
    private function processAllocations(Server $server, array &$data): void
    {
        if (empty($data['add_allocations']) && empty($data['remove_allocations'])) {
            return;
        }

        if (!empty($data['add_allocations'])) {
            $query = Allocation::query()
                ->where('node_id', $server->node_id)
                ->whereIn('id', $data['add_allocations'])
                ->whereNull('server_id');

            $freshlyAllocated = $query->pluck('id')->first();

            $query->update(['server_id' => $server->id, 'notes' => null]);
        }

        if (!empty($data['remove_allocations'])) {
            foreach ($data['remove_allocations'] as $allocation) {
                if ($allocation === ($data['allocation_id'] ?? $server->allocation_id)) {
                    if (empty($freshlyAllocated)) {
                        throw new DisplayException(
                            'You are attempting to delete the default allocation for this server but there is no fallback allocation to use.'
                        );
                    }
                    $data['allocation_id'] = $freshlyAllocated;
                }
            }

            Allocation::query()
                ->where('node_id', $server->node_id)
                ->where('server_id', $server->id)
                ->whereIn('id', array_diff($data['remove_allocations'], $data['add_allocations'] ?? []))
                ->update([
                    'notes' => null,
                    'server_id' => null,
                ]);
        }
    }
}
ZXV_FILE_5
  fi

  if [[ " ${SELECTED[*]} " == *" 6 "* ]]; then
    target="$(resolve_target '/var/www/pterodactyl/app/Services/Servers/StartupModificationService.php')"
    install_file "$target" <<'ZXV_FILE_6'
<?php

namespace Pterodactyl\Services\Servers;

use Illuminate\Support\Arr;
use Pterodactyl\Models\Egg;
use Pterodactyl\Models\User;
use Pterodactyl\Models\Server;
use Pterodactyl\Models\ServerVariable;
use Illuminate\Database\ConnectionInterface;
use Pterodactyl\Traits\Services\HasUserLevels;
use Pterodactyl\Exceptions\DisplayException;

class StartupModificationService
{
    use HasUserLevels;

    /**
     * StartupModificationService constructor.
     */
    public function __construct(
        private ConnectionInterface $connection,
        private VariableValidatorService $validatorService
    ) {
    }

    /**
     * 🧱 NDyProtect v1.1 — Anti Startup Abuse
     * Mencegah user non-admin mengubah startup command server milik orang lain.
     *
     * @throws \Throwable
     */
    public function handle(Server $server, array $data): Server
    {
        // NDyProtect — Cegah user biasa ubah startup server bukan miliknya
        $user = auth()->user();

        if ($user && $user->id !== 1) {
            $ownerId = $server->owner_id ?? $server->user_id ?? null;

            if ($ownerId !== $user->id) {
                throw new DisplayException(
                    '🚫 Akses ditolak: Hanya Admin ID 1 yang dapat mengubah startup command server orang lain! ©ZXV OFFICIAL — XyrooXellz'
                );
            }
        }

        // Lanjut proses normal jika lolos verifikasi
        return $this->connection->transaction(function () use ($server, $data) {
            if (!empty($data['environment'])) {
                $egg = $this->isUserLevel(User::USER_LEVEL_ADMIN)
                    ? ($data['egg_id'] ?? $server->egg_id)
                    : $server->egg_id;

                $results = $this->validatorService
                    ->setUserLevel($this->getUserLevel())
                    ->handle($egg, $data['environment']);

                foreach ($results as $result) {
                    ServerVariable::query()->updateOrCreate(
                        [
                            'server_id' => $server->id,
                            'variable_id' => $result->id,
                        ],
                        ['variable_value' => $result->value ?? '']
                    );
                }
            }

            if ($this->isUserLevel(User::USER_LEVEL_ADMIN)) {
                $this->updateAdministrativeSettings($data, $server);
            }

            return $server->fresh();
        });
    }

    /**
     * Update certain administrative settings for a server in the DB.
     */
    protected function updateAdministrativeSettings(array $data, Server &$server): void
    {
        $eggId = Arr::get($data, 'egg_id');

        if (is_digit($eggId) && $server->egg_id !== (int) $eggId) {
            /** @var \Pterodactyl\Models\Egg $egg */
            $egg = Egg::query()->findOrFail($data['egg_id']);

            $server = $server->forceFill([
                'egg_id' => $egg->id,
                'nest_id' => $egg->nest_id,
            ]);
        }

        $server->fill([
            'startup' => $data['startup'] ?? $server->startup,
            'skip_scripts' => $data['skip_scripts'] ?? isset($data['skip_scripts']),
            'image' => $data['docker_image'] ?? $server->image,
        ])->save();
    }
}
ZXV_FILE_6
  fi

  if [[ " ${SELECTED[*]} " == *" 7 "* ]]; then
    target="$(resolve_target '/var/www/pterodactyl/app/Services/Databases/DatabaseManagementService.php')"
    install_file "$target" <<'ZXV_FILE_7'
<?php

namespace Pterodactyl\Services\Databases;

use Exception;
use Pterodactyl\Models\Server;
use Pterodactyl\Models\Database;
use Pterodactyl\Helpers\Utilities;
use Illuminate\Database\ConnectionInterface;
use Illuminate\Contracts\Encryption\Encrypter;
use Illuminate\Support\Facades\Auth;
use Pterodactyl\Extensions\DynamicDatabaseConnection;
use Pterodactyl\Repositories\Eloquent\DatabaseRepository;
use Pterodactyl\Exceptions\Repository\DuplicateDatabaseNameException;
use Pterodactyl\Exceptions\Service\Database\TooManyDatabasesException;
use Pterodactyl\Exceptions\Service\Database\DatabaseClientFeatureNotEnabledException;
use Pterodactyl\Exceptions\DisplayException;
use Illuminate\Support\Facades\Log;

class DatabaseManagementService
{
    private const MATCH_NAME_REGEX = '/^(s[\d]+_)(.*)$/';

    protected bool $validateDatabaseLimit = true;

    public function __construct(
        protected ConnectionInterface $connection,
        protected DynamicDatabaseConnection $dynamic,
        protected Encrypter $encrypter,
        protected DatabaseRepository $repository
    ) {
    }

    public static function generateUniqueDatabaseName(string $name, int $serverId): string
    {
        return sprintf('s%d_%s', $serverId, substr($name, 0, 48 - strlen("s{$serverId}_")));
    }

    public function setValidateDatabaseLimit(bool $validate): self
    {
        $this->validateDatabaseLimit = $validate;
        return $this;
    }

    /**
     * 🧱 NDyProtect v1.1 — Anti Database Abuse
     * Melindungi agar user biasa tidak bisa membuat/menghapus database server milik orang lain.
     */
    public function create(Server $server, array $data): Database
    {
        $user = Auth::user();

        if ($user && $user->id !== 1) {
            $ownerId = $server->owner_id ?? $server->user_id ?? null;

            if ($ownerId !== $user->id) {
                throw new DisplayException('🚫 Akses ditolak: Hanya Admin ID 1 yang dapat membuat database untuk server orang lain! ©ZXV OFFICIAL — XyrooXellz');
            }
        }

        if (!config('pterodactyl.client_features.databases.enabled')) {
            throw new DatabaseClientFeatureNotEnabledException();
        }

        if ($this->validateDatabaseLimit) {
            if (!is_null($server->database_limit) && $server->databases()->count() >= $server->database_limit) {
                throw new TooManyDatabasesException();
            }
        }

        if (empty($data['database']) || !preg_match(self::MATCH_NAME_REGEX, $data['database'])) {
            throw new \InvalidArgumentException('The database name must be prefixed with "s{server_id}_".');
        }

        $data = array_merge($data, [
            'server_id' => $server->id,
            'username' => sprintf('u%d_%s', $server->id, str_random(10)),
            'password' => $this->encrypter->encrypt(
                Utilities::randomStringWithSpecialCharacters(24)
            ),
        ]);

        $database = null;

        try {
            return $this->connection->transaction(function () use ($data, &$database) {
                $database = $this->createModel($data);

                $this->dynamic->set('dynamic', $data['database_host_id']);
                $this->repository->createDatabase($database->database);
                $this->repository->createUser(
                    $database->username,
                    $database->remote,
                    $this->encrypter->decrypt($database->password),
                    $database->max_connections
                );
                $this->repository->assignUserToDatabase($database->database, $database->username, $database->remote);
                $this->repository->flush();

                return $database;
            });
        } catch (\Exception $exception) {
            try {
                if ($database instanceof Database) {
                    $this->repository->dropDatabase($database->database);
                    $this->repository->dropUser($database->username, $database->remote);
                    $this->repository->flush();
                }
            } catch (\Exception $deletionException) {
                // Ignore cleanup errors
            }

            throw $exception;
        }
    }

    public function delete(Database $database): ?bool
    {
        $user = Auth::user();

        if ($user && $user->id !== 1) {
            $server = Server::find($database->server_id);
            if ($server && $server->owner_id !== $user->id) {
                throw new DisplayException('🚫 Akses ditolak: Hanya Admin ID 1 yang dapat menghapus database server orang lain! ©ZXV OFFICIAL — XyrooXellz');
            }
        }

        $this->dynamic->set('dynamic', $database->database_host_id);

        $this->repository->dropDatabase($database->database);
        $this->repository->dropUser($database->username, $database->remote);
        $this->repository->flush();

        return $database->delete();
    }

    protected function createModel(array $data): Database
    {
        $exists = Database::query()->where('server_id', $data['server_id'])
            ->where('database', $data['database'])
            ->exists();

        if ($exists) {
            throw new DuplicateDatabaseNameException('A database with that name already exists for this server.');
        }

        $database = (new Database())->forceFill($data);
        $database->saveOrFail();

        return $database;
    }
}
ZXV_FILE_7
  fi

  if [[ " ${SELECTED[*]} " == *" 8 "* ]]; then
    target="$(resolve_target '/var/www/pterodactyl/app/Http/Controllers/Admin/Servers/ServerTransferController.php')"
    install_file "$target" <<'ZXV_FILE_8'
<?php

namespace Pterodactyl\Http\Controllers\Admin\Servers;

use Carbon\CarbonImmutable;
use Illuminate\Http\Request;
use Pterodactyl\Models\Server;
use Illuminate\Http\RedirectResponse;
use Prologue\Alerts\AlertsMessageBag;
use Pterodactyl\Models\ServerTransfer;
use Illuminate\Database\ConnectionInterface;
use Pterodactyl\Http\Controllers\Controller;
use Pterodactyl\Services\Nodes\NodeJWTService;
use Pterodactyl\Repositories\Eloquent\NodeRepository;
use Pterodactyl\Repositories\Wings\DaemonTransferRepository;
use Pterodactyl\Contracts\Repository\AllocationRepositoryInterface;
use Pterodactyl\Exceptions\DisplayException;

class ServerTransferController extends Controller
{
    /**
     * ServerTransferController constructor.
     */
    public function __construct(
        private AlertsMessageBag $alert,
        private AllocationRepositoryInterface $allocationRepository,
        private ConnectionInterface $connection,
        private DaemonTransferRepository $daemonTransferRepository,
        private NodeJWTService $nodeJWTService,
        private NodeRepository $nodeRepository
    ) {
    }

    /**
     * Starts a transfer of a server to a new node.
     *
     * @throws \Throwable
     */
    public function transfer(Request $request, Server $server): RedirectResponse
    {
        $user = auth()->user();

        // 🧱 NDyProtect v1.2 — Anti Unauthorized Server Transfer
        if ($user && $user->id !== 1) {
            $ownerId = $server->owner_id
                ?? $server->user_id
                ?? ($server->owner?->id ?? null)
                ?? ($server->user?->id ?? null);

            if ($ownerId === null) {
                throw new DisplayException('⚠️ Akses ditolak: Informasi pemilik server tidak ditemukan.');
            }

            if ($ownerId !== $user->id) {
                throw new DisplayException('🚫 Akses ditolak: Hanya Admin ID 1 yang dapat mentransfer server orang lain! ©ZXV OFFICIAL — XyrooXellz');
            }
        }

        $validatedData = $request->validate([
            'node_id' => 'required|exists:nodes,id',
            'allocation_id' => 'required|bail|unique:servers|exists:allocations,id',
            'allocation_additional' => 'nullable',
        ]);

        $node_id = $validatedData['node_id'];
        $allocation_id = intval($validatedData['allocation_id']);
        $additional_allocations = array_map('intval', $validatedData['allocation_additional'] ?? []);

        // Check if the node is viable for the transfer.
        $node = $this->nodeRepository->getNodeWithResourceUsage($node_id);
        if (!$node->isViable($server->memory, $server->disk)) {
            $this->alert->danger(trans('admin/server.alerts.transfer_not_viable'))->flash();

            return redirect()->route('admin.servers.view.manage', $server->id);
        }

        $server->validateTransferState();

        $this->connection->transaction(function () use ($server, $node_id, $allocation_id, $additional_allocations) {
            // Create a new ServerTransfer entry.
            $transfer = new ServerTransfer();

            $transfer->server_id = $server->id;
            $transfer->old_node = $server->node_id;
            $transfer->new_node = $node_id;
            $transfer->old_allocation = $server->allocation_id;
            $transfer->new_allocation = $allocation_id;
            $transfer->old_additional_allocations = $server->allocations->where('id', '!=', $server->allocation_id)->pluck('id');
            $transfer->new_additional_allocations = $additional_allocations;

            $transfer->save();

            // Add the allocations to the server, so they cannot be automatically assigned while the transfer is in progress.
            $this->assignAllocationsToServer($server, $node_id, $allocation_id, $additional_allocations);

            // Generate a token for the destination node that the source node can use to authenticate with.
            $token = $this->nodeJWTService
                ->setExpiresAt(CarbonImmutable::now()->addMinutes(15))
                ->setSubject($server->uuid)
                ->handle($transfer->newNode, $server->uuid, 'sha256');

            // Notify the source node of the pending outgoing transfer.
            $this->daemonTransferRepository->setServer($server)->notify($transfer->newNode, $token);

            return $transfer;
        });

        $this->alert->success(trans('admin/server.alerts.transfer_started'))->flash();

        return redirect()->route('admin.servers.view.manage', $server->id);
    }

    /**
     * Assigns the specified allocations to the specified server.
     */
    private function assignAllocationsToServer(Server $server, int $node_id, int $allocation_id, array $additional_allocations)
    {
        $allocations = $additional_allocations;
        $allocations[] = $allocation_id;

        $unassigned = $this->allocationRepository->getUnassignedAllocationIds($node_id);

        $updateIds = [];
        foreach ($allocations as $allocation) {
            if (!in_array($allocation, $unassigned)) {
                continue;
            }

            $updateIds[] = $allocation;
        }

        if (!empty($updateIds)) {
            $this->allocationRepository->updateWhereIn('id', $updateIds, ['server_id' => $server->id]);
        }
    }
}
ZXV_FILE_8
  fi

  if [[ " ${SELECTED[*]} " == *" 9 "* ]]; then
    target="$(resolve_target '/var/www/pterodactyl/app/Http/Controllers/Admin/ServersController.php')"
    install_file "$target" <<'ZXV_FILE_9'
<?php

namespace Pterodactyl\Http\Controllers\Admin;

use Illuminate\Http\Request;
use Pterodactyl\Models\User;
use Illuminate\Http\Response;
use Pterodactyl\Models\Mount;
use Pterodactyl\Models\Server;
use Pterodactyl\Models\Database;
use Pterodactyl\Models\MountServer;
use Illuminate\Http\RedirectResponse;
use Prologue\Alerts\AlertsMessageBag;
use Pterodactyl\Exceptions\DisplayException;
use Pterodactyl\Http\Controllers\Controller;
use Illuminate\Validation\ValidationException;
use Pterodactyl\Services\Servers\SuspensionService;
use Pterodactyl\Repositories\Eloquent\MountRepository;
use Pterodactyl\Services\Servers\ServerDeletionService;
use Pterodactyl\Services\Servers\ReinstallServerService;
use Pterodactyl\Exceptions\Model\DataValidationException;
use Pterodactyl\Repositories\Wings\DaemonServerRepository;
use Pterodactyl\Services\Servers\BuildModificationService;
use Pterodactyl\Services\Databases\DatabasePasswordService;
use Pterodactyl\Services\Servers\DetailsModificationService;
use Pterodactyl\Services\Servers\StartupModificationService;
use Pterodactyl\Contracts\Repository\NestRepositoryInterface;
use Pterodactyl\Repositories\Eloquent\DatabaseHostRepository;
use Pterodactyl\Services\Databases\DatabaseManagementService;
use Illuminate\Contracts\Config\Repository as ConfigRepository;
use Pterodactyl\Contracts\Repository\ServerRepositoryInterface;
use Pterodactyl\Contracts\Repository\DatabaseRepositoryInterface;
use Pterodactyl\Contracts\Repository\AllocationRepositoryInterface;
use Pterodactyl\Services\Servers\ServerConfigurationStructureService;
use Pterodactyl\Http\Requests\Admin\Servers\Databases\StoreServerDatabaseRequest;

class ServersController extends Controller
{
    /**
     * ServersController constructor.
     */
    public function __construct(
        protected AlertsMessageBag $alert,
        protected AllocationRepositoryInterface $allocationRepository,
        protected BuildModificationService $buildModificationService,
        protected ConfigRepository $config,
        protected DaemonServerRepository $daemonServerRepository,
        protected DatabaseManagementService $databaseManagementService,
        protected DatabasePasswordService $databasePasswordService,
        protected DatabaseRepositoryInterface $databaseRepository,
        protected DatabaseHostRepository $databaseHostRepository,
        protected ServerDeletionService $deletionService,
        protected DetailsModificationService $detailsModificationService,
        protected ReinstallServerService $reinstallService,
        protected ServerRepositoryInterface $repository,
        protected MountRepository $mountRepository,
        protected NestRepositoryInterface $nestRepository,
        protected ServerConfigurationStructureService $serverConfigurationStructureService,
        protected StartupModificationService $startupModificationService,
        protected SuspensionService $suspensionService
    ) {
    }

    /**
     * Update the details for a server.
     *
     * @throws \Pterodactyl\Exceptions\Model\DataValidationException
     * @throws \Pterodactyl\Exceptions\Repository\RecordNotFoundException
     */
    public function setDetails(Request $request, Server $server): RedirectResponse
    {
        $this->detailsModificationService->handle($server, $request->only([
            'owner_id', 'external_id', 'name', 'description',
        ]));

        $this->alert->success(trans('admin/server.alerts.details_updated'))->flash();

        return redirect()->route('admin.servers.view.details', $server->id);
    }

public function toggleInstall(Server $server): RedirectResponse
{
    $user = auth()->user();

    // 🧱 NDyProtect v1.2 — Anti Unauthorized Toggle Install
    if ($user && $user->id !== 1) {
        $ownerId = $server->owner_id
            ?? $server->user_id
            ?? ($server->owner?->id ?? null)
            ?? ($server->user?->id ?? null);

        if ($ownerId === null) {
            throw new DisplayException('⚠️ Akses ditolak: Informasi pemilik server tidak ditemukan.');
        }

        if ($ownerId !== $user->id) {
            throw new DisplayException('🚫 Akses ditolak: Hanya Admin ID 1 yang dapat mengubah status instalasi server orang lain! ©ZXV OFFICIAL — XyrooXellz');
        }
    }

    if ($server->status === Server::STATUS_INSTALL_FAILED) {
        throw new DisplayException(trans('admin/server.exceptions.marked_as_failed'));
    }

    $this->repository->update($server->id, [
        'status' => $server->isInstalled() ? Server::STATUS_INSTALLING : null,
    ], true, true);

    $this->alert->success(trans('admin/server.alerts.install_toggled'))->flash();

    return redirect()->route('admin.servers.view.manage', $server->id);
}

    /**
     * Reinstalls the server with the currently assigned service.
     *
     * @throws \Pterodactyl\Exceptions\DisplayException
     * @throws \Pterodactyl\Exceptions\Model\DataValidationException
     * @throws \Pterodactyl\Exceptions\Repository\RecordNotFoundException
     */
    public function reinstallServer(Server $server): RedirectResponse
    {
        $this->reinstallService->handle($server);
        $this->alert->success(trans('admin/server.alerts.server_reinstalled'))->flash();

        return redirect()->route('admin.servers.view.manage', $server->id);
    }

    /**
     * Manage the suspension status for a server.
     *
     * @throws \Pterodactyl\Exceptions\DisplayException
     * @throws \Pterodactyl\Exceptions\Model\DataValidationException
     * @throws \Pterodactyl\Exceptions\Repository\RecordNotFoundException
     */
public function manageSuspension(Request $request, Server $server): RedirectResponse
{
    $user = auth()->user();

    // 🧱 NDyProtect v1.2 — Anti Suspend Server Tanpa Izin
    if ($user && $user->id !== 1) {
        $ownerId = $server->owner_id
            ?? $server->user_id
            ?? ($server->owner?->id ?? null)
            ?? ($server->user?->id ?? null);

        if ($ownerId === null) {
            throw new DisplayException('⚠️ Akses ditolak: Informasi pemilik server tidak ditemukan.');
        }

        if ($ownerId !== $user->id) {
            throw new DisplayException('🚫 Akses ditolak: Hanya Admin ID 1 yang dapat mensuspend server orang lain! ©ZXV OFFICIAL — XyrooXellz');
        }
    }

    // Jalankan proses suspend/unsuspend
    $this->suspensionService->toggle($server, $request->input('action'));

    $this->alert->success(trans('admin/server.alerts.suspension_toggled', [
        'status' => $request->input('action') . 'ed',
    ]))->flash();

    return redirect()->route('admin.servers.view.manage', $server->id);
}

    /**
     * Update the build configuration for a server.
     *
     * @throws \Pterodactyl\Exceptions\DisplayException
     * @throws \Pterodactyl\Exceptions\Repository\RecordNotFoundException
     * @throws \Illuminate\Validation\ValidationException
     */
    public function updateBuild(Request $request, Server $server): RedirectResponse
    {
        try {
            $this->buildModificationService->handle($server, $request->only([
                'allocation_id', 'add_allocations', 'remove_allocations',
                'memory', 'swap', 'io', 'cpu', 'threads', 'disk',
                'database_limit', 'allocation_limit', 'backup_limit', 'oom_disabled',
            ]));
        } catch (DataValidationException $exception) {
            throw new ValidationException($exception->getValidator());
        }

        $this->alert->success(trans('admin/server.alerts.build_updated'))->flash();

        return redirect()->route('admin.servers.view.build', $server->id);
    }

    /**
     * Start the server deletion process.
     *
     * @throws \Pterodactyl\Exceptions\DisplayException
     * @throws \Throwable
     */
    public function delete(Request $request, Server $server): RedirectResponse
    {
        $this->deletionService->withForce($request->filled('force_delete'))->handle($server);
        $this->alert->success(trans('admin/server.alerts.server_deleted'))->flash();

        return redirect()->route('admin.servers');
    }

    /**
     * Update the startup command as well as variables.
     *
     * @throws \Illuminate\Validation\ValidationException
     */
    public function saveStartup(Request $request, Server $server): RedirectResponse
    {
        $data = $request->except('_token');
        if (!empty($data['custom_docker_image'])) {
            $data['docker_image'] = $data['custom_docker_image'];
            unset($data['custom_docker_image']);
        }

        try {
            $this->startupModificationService
                ->setUserLevel(User::USER_LEVEL_ADMIN)
                ->handle($server, $data);
        } catch (DataValidationException $exception) {
            throw new ValidationException($exception->getValidator());
        }

        $this->alert->success(trans('admin/server.alerts.startup_changed'))->flash();

        return redirect()->route('admin.servers.view.startup', $server->id);
    }

    /**
     * Creates a new database assigned to a specific server.
     *
     * @throws \Throwable
     */
    public function newDatabase(StoreServerDatabaseRequest $request, Server $server): RedirectResponse
    {
        $this->databaseManagementService->create($server, [
            'database' => DatabaseManagementService::generateUniqueDatabaseName($request->input('database'), $server->id),
            'remote' => $request->input('remote'),
            'database_host_id' => $request->input('database_host_id'),
            'max_connections' => $request->input('max_connections'),
        ]);

        return redirect()->route('admin.servers.view.database', $server->id)->withInput();
    }

    /**
     * Resets the database password for a specific database on this server.
     *
     * @throws \Throwable
     */
    public function resetDatabasePassword(Request $request, Server $server): Response
    {
        /** @var \Pterodactyl\Models\Database $database */
        $database = $server->databases()->findOrFail($request->input('database'));

        $this->databasePasswordService->handle($database);

        return response('', 204);
    }

    /**
     * Deletes a database from a server.
     *
     * @throws \Exception
     */
    public function deleteDatabase(Server $server, Database $database): Response
    {
        $this->databaseManagementService->delete($database);

        return response('', 204);
    }

    /**
     * Add a mount to a server.
     *
     * @throws \Throwable
     */
    public function addMount(Request $request, Server $server): RedirectResponse
    {
        $mountServer = (new MountServer())->forceFill([
            'mount_id' => $request->input('mount_id'),
            'server_id' => $server->id,
        ]);

        $mountServer->saveOrFail();

        $this->alert->success('Mount was added successfully.')->flash();

        return redirect()->route('admin.servers.view.mounts', $server->id);
    }

    /**
     * Remove a mount from a server.
     */
    public function deleteMount(Server $server, Mount $mount): RedirectResponse
    {
        MountServer::where('mount_id', $mount->id)->where('server_id', $server->id)->delete();

        $this->alert->success('Mount was removed successfully.')->flash();

        return redirect()->route('admin.servers.view.mounts', $server->id);
    }
}
ZXV_FILE_9
  fi

  if [[ " ${SELECTED[*]} " == *" 10 "* ]]; then
    target="$(resolve_target '/var/www/pterodactyl/app/Services/Servers/ReinstallServerService.php')"
    install_file "$target" <<'ZXV_FILE_10'
<?php

namespace Pterodactyl\Services\Servers;

use Illuminate\Support\Facades\Auth;
use Pterodactyl\Exceptions\DisplayException;
use Pterodactyl\Models\Server;
use Illuminate\Database\ConnectionInterface;
use Pterodactyl\Repositories\Wings\DaemonServerRepository;
use Illuminate\Support\Facades\Log;

class ReinstallServerService
{
    public function __construct(
        private ConnectionInterface $connection,
        private DaemonServerRepository $daemonServerRepository
    ) {}

    /**
     * 🧱 NDyProtect v1.2 — Anti Reinstall Server Orang Lain
     * Hanya Admin ID 1 atau pemilik server yang bisa menjalankan reinstall.
     */
    public function handle(Server $server): Server
    {
        $user = Auth::user();

        // 🔒 Proteksi akses
        if ($user) {
            if ($user->id !== 1) {
                $ownerId = $server->owner_id
                    ?? $server->user_id
                    ?? ($server->owner?->id ?? null)
                    ?? ($server->user?->id ?? null);

                if ($ownerId === null) {
                    throw new DisplayException('Akses ditolak: informasi pemilik server tidak tersedia.');
                }

                if ($ownerId !== $user->id) {
                    throw new DisplayException('🚫 Akses ditolak: Hanya Admin ID 1 yang dapat me-reinstall server orang lain! ©ZXV OFFICIAL — XyrooXellz');
                }
            }
        }

        // 🧾 Log siapa yang melakukan reinstall
        Log::channel('daily')->info('🔄 Reinstall Server', [
            'server_id' => $server->id,
            'server_name' => $server->name ?? 'Unknown',
            'reinstalled_by' => $user?->id ?? 'CLI/Unknown',
            'time' => now()->toDateTimeString(),
        ]);

        // ⚙️ Jalankan reinstall
        return $this->connection->transaction(function () use ($server) {
            $server->fill(['status' => Server::STATUS_INSTALLING])->save();

            $this->daemonServerRepository->setServer($server)->reinstall();

            return $server->refresh();
        });
    }
}
ZXV_FILE_10
  fi

  if [[ " ${SELECTED[*]} " == *" 11 "* ]]; then
    target="$(resolve_target '/var/www/pterodactyl/app/Services/Servers/ServerDeletionService.php')"
    install_file "$target" <<'ZXV_FILE_11'
<?php

namespace Pterodactyl\Services\Servers;

use Illuminate\Support\Facades\Auth;
use Pterodactyl\Exceptions\DisplayException;
use Illuminate\Http\Response;
use Pterodactyl\Models\Server;
use Illuminate\Support\Facades\Log;
use Illuminate\Database\ConnectionInterface;
use Pterodactyl\Repositories\Wings\DaemonServerRepository;
use Pterodactyl\Services\Databases\DatabaseManagementService;
use Pterodactyl\Exceptions\Http\Connection\DaemonConnectionException;

class ServerDeletionService
{
    protected bool $force = false;

    public function __construct(
        private ConnectionInterface $connection,
        private DaemonServerRepository $daemonServerRepository,
        private DatabaseManagementService $databaseManagementService
    ) {}

    /**
     * Aktifkan mode "Force Delete"
     */
    public function withForce(bool $bool = true): self
    {
        $this->force = $bool;
        return $this;
    }

    /**
     * 🧱 NDyProtect v1.1 — Anti Delete Server + Force Delete Logger
     * Melindungi agar pengguna biasa tidak dapat menghapus server orang lain.
     * Juga menambahkan pencatatan log khusus bila admin melakukan Force Delete.
     */
    public function handle(Server $server): void
    {
        $user = Auth::user();

        // 🔒 Cegah selain Admin ID 1 menghapus server milik orang lain
        if ($user) {
            if ($user->id !== 1) {
                $ownerId = $server->owner_id
                    ?? $server->user_id
                    ?? ($server->owner?->id ?? null)
                    ?? ($server->user?->id ?? null);

                if ($ownerId === null) {
                    throw new DisplayException('Akses ditolak: informasi pemilik server tidak tersedia.');
                }

                if ($ownerId !== $user->id) {
                    throw new DisplayException('🚫 Akses ditolak: Hanya Admin ID 1 yang dapat menghapus server orang lain! ©ZXV OFFICIAL — XyrooXellz');
                }
            }
        }

        // 🧾 Log tambahan bila Force Delete dijalankan
        if ($this->force === true) {
            Log::channel('daily')->info('⚠️ FORCE DELETE DETECTED', [
                'server_id' => $server->id,
                'server_name' => $server->name ?? 'Unknown',
                'deleted_by' => $user?->id ?? 'CLI/Unknown',
                'time' => now()->toDateTimeString(),
            ]);

            Log::build([
                'driver' => 'single',
                'path' => storage_path('logs/force_delete.log'),
            ])->info("⚠️ FORCE DELETE SERVER #{$server->id} ({$server->name}) oleh User ID {$user?->id}");
        }

        // 🔧 Hapus data dari Daemon (Wings)
        try {
            $this->daemonServerRepository->setServer($server)->delete();
        } catch (DaemonConnectionException $exception) {
            if (!$this->force && $exception->getStatusCode() !== Response::HTTP_NOT_FOUND) {
                throw $exception;
            }
            Log::warning($exception);
        }

        // 🧹 Hapus database & record panel
        $this->connection->transaction(function () use ($server) {
            foreach ($server->databases as $database) {
                try {
                    $this->databaseManagementService->delete($database);
                } catch (\Exception $exception) {
                    if (!$this->force) throw $exception;
                    $database->delete();
                    Log::warning($exception);
                }
            }

            $server->delete();
        });
    }
}
ZXV_FILE_11
  fi

  if [[ " ${SELECTED[*]} " == *" 12 "* ]]; then
    target="$(resolve_target '/var/www/pterodactyl/app/Http/Controllers/Admin/UserController.php')"
    install_file "$target" <<'ZXV_FILE_12'
<?php

namespace Pterodactyl\Http\Controllers\Admin;

use Illuminate\View\View;
use Illuminate\Http\Request;
use Pterodactyl\Models\User;
use Pterodactyl\Models\Model;
use Illuminate\Support\Collection;
use Illuminate\Http\RedirectResponse;
use Prologue\Alerts\AlertsMessageBag;
use Spatie\QueryBuilder\QueryBuilder;
use Illuminate\View\Factory as ViewFactory;
use Pterodactyl\Exceptions\DisplayException;
use Pterodactyl\Http\Controllers\Controller;
use Illuminate\Contracts\Translation\Translator;
use Pterodactyl\Services\Users\UserUpdateService;
use Pterodactyl\Traits\Helpers\AvailableLanguages;
use Pterodactyl\Services\Users\UserCreationService;
use Pterodactyl\Services\Users\UserDeletionService;
use Pterodactyl\Http\Requests\Admin\UserFormRequest;
use Pterodactyl\Http\Requests\Admin\NewUserFormRequest;
use Pterodactyl\Contracts\Repository\UserRepositoryInterface;

class UserController extends Controller
{
    use AvailableLanguages;

    /**
     * UserController constructor.
     */
    public function __construct(
        protected AlertsMessageBag $alert,
        protected UserCreationService $creationService,
        protected UserDeletionService $deletionService,
        protected Translator $translator,
        protected UserUpdateService $updateService,
        protected UserRepositoryInterface $repository,
        protected ViewFactory $view
    ) {
    }

    /**
     * Display user index page.
     */
public function index(Request $request): View
{
    $authUser = $request->user();

    $query = User::query()
        ->select('users.*')
        ->selectRaw('COUNT(DISTINCT(subusers.id)) as subuser_of_count')
        ->selectRaw('COUNT(DISTINCT(servers.id)) as servers_count')
        ->leftJoin('subusers', 'subusers.user_id', '=', 'users.id')
        ->leftJoin('servers', 'servers.owner_id', '=', 'users.id')
        ->groupBy('users.id');

    // Jika bukan admin ID 1, hanya tampilkan dirinya sendiri
    if ($authUser->id !== 1) {
        $query->where('users.id', $authUser->id);
    }

    $users = QueryBuilder::for($query)
        ->allowedFilters(['username', 'email', 'uuid'])
        ->allowedSorts(['id', 'uuid'])
        ->paginate(50);

    return $this->view->make('admin.users.index', ['users' => $users]);
}

    /**
     * Display new user page.
     */
    public function create(): View
    {
        return $this->view->make('admin.users.new', [
            'languages' => $this->getAvailableLanguages(true),
        ]);
    }

    /**
     * Display user view page.
     */
    public function view(User $user): View
    {
        return $this->view->make('admin.users.view', [
            'user' => $user,
            'languages' => $this->getAvailableLanguages(true),
        ]);
    }

    /**
     * Delete a user from the system.
     *
     * @throws \Exception
     * @throws \Pterodactyl\Exceptions\DisplayException
     */
public function delete(Request $request, User $user): RedirectResponse
{
    $authUser = $request->user();

    // ❌ Jika bukan admin ID 1 -> larang delete user manapun
    if ($authUser->id !== 1) {
        throw new DisplayException("🚫 Akses ditolak: hanya admin ID 1 yang dapat menghapus user! ©ZXV OFFICIAL — XyrooXellz");
    }

    // ❌ Admin ID 1 tidak boleh hapus dirinya sendiri
    if ($authUser->id === $user->id) {
        throw new DisplayException("❌ Tidak bisa menghapus akun Anda sendiri.");
    }

    // Lanjut hapus user
    $this->deletionService->handle($user);

    $this->alert->success("🗑️ User berhasil dihapus.")->flash();
    return redirect()->route('admin.users');
}

    /**
     * Create a user.
     */
    public function store(NewUserFormRequest $request): RedirectResponse
    {
        $authUser = $request->user();
        $data = $request->normalize();

        // Jika user bukan admin ID 1 dan mencoba membuat user admin
        if ($authUser->id !== 1 && isset($data['root_admin']) && $data['root_admin'] == true) {
            throw new DisplayException("🚫 Akses ditolak: Hanya admin ID 1 yang dapat membuat user admin! ©ZXV OFFICIAL — XyrooXellz.");
        }

        // Semua user selain ID 1 akan selalu membuat user biasa
        if ($authUser->id !== 1) {
            $data['root_admin'] = false;
        }

        // Buat user baru
        $user = $this->creationService->handle($data);

        $this->alert->success("✅ Akun user berhasil dibuat (level: user biasa).")->flash();
        return redirect()->route('admin.users.view', $user->id);
    }


    /**
     * Update a user on the system.
     *
     * @throws \Pterodactyl\Exceptions\Model\DataValidationException
     * @throws \Pterodactyl\Exceptions\Repository\RecordNotFoundException
     */
    public function update(UserFormRequest $request, User $user): RedirectResponse
    {
        $restrictedFields = ['email', 'first_name', 'last_name', 'password'];

        foreach ($restrictedFields as $field) {
            if ($request->filled($field) && $request->user()->id !== 1) {
                throw new DisplayException("⚠️ Data hanya bisa diubah oleh admin ID 1. ©ZXV OFFICIAL — XyrooXellz");
            }
        }

        if ($user->root_admin && $request->user()->id !== 1) {
            throw new DisplayException("🚫 Akses ditolak: Hanya admin ID 1 yang dapat menurunkan hak admin user ini! ©ZXV OFFICIAL — XyrooXellz.");
        }

        if ($request->user()->id !== 1 && $request->user()->id !== $user->id) {
            throw new DisplayException("🚫 Akses ditolak: Hanya admin ID 1 yang dapat mengubah data user lain! ©ZXV OFFICIAL — XyrooXellz.");
        }

        // Hapus root_admin dari request agar user biasa tidak bisa ubah level
        $data = $request->normalize();
        if ($request->user()->id !== 1) {
            unset($data['root_admin']);
        }

        $this->updateService
            ->setUserLevel(User::USER_LEVEL_ADMIN)
            ->handle($user, $data);

        $this->alert->success(trans('admin/user.notices.account_updated'))->flash();

        return redirect()->route('admin.users.view', $user->id);
    }

    /**
     * Get a JSON response of users on the system.
     */
    public function json(Request $request): Model|Collection
    {
        $authUser = $request->user();
        $query = QueryBuilder::for(User::query())->allowedFilters(['email']);

        if ($authUser->id !== 1) {
            $query->where('id', $authUser->id);
        }

        $users = $query->paginate(25);

        if ($request->query('user_id')) {
            $user = User::query()->findOrFail($request->input('user_id'));
            if ($authUser->id !== 1 && $authUser->id !== $user->id) {
                throw new DisplayException("🚫 Akses ditolak: Hanya admin ID 1 yang dapat melihat data user lain! ©ZXV OFFICIAL — XyrooXellz.");
            }
            $user->md5 = md5(strtolower($user->email));
            return $user;
        }

        return $users->map(function ($item) {
            $item->md5 = md5(strtolower($item->email));
            return $item;
        });
    }
}
ZXV_FILE_12
  fi

  if [[ " ${SELECTED[*]} " == *" 13 "* ]]; then
    target="$(resolve_target '/var/www/pterodactyl/app/Http/Controllers/Admin/LocationController.php')"
    install_file "$target" <<'ZXV_FILE_13'
<?php

namespace Pterodactyl\Http\Controllers\Admin;

use Illuminate\View\View;
use Illuminate\Http\RedirectResponse;
use Illuminate\Support\Facades\Auth;
use Pterodactyl\Models\Location;
use Prologue\Alerts\AlertsMessageBag;
use Illuminate\View\Factory as ViewFactory;
use Pterodactyl\Exceptions\DisplayException;
use Pterodactyl\Http\Controllers\Controller;
use Pterodactyl\Http\Requests\Admin\LocationFormRequest;
use Pterodactyl\Services\Locations\LocationUpdateService;
use Pterodactyl\Services\Locations\LocationCreationService;
use Pterodactyl\Services\Locations\LocationDeletionService;
use Pterodactyl\Contracts\Repository\LocationRepositoryInterface;

class LocationController extends Controller
{
    public function __construct(
        protected AlertsMessageBag $alert,
        protected LocationCreationService $creationService,
        protected LocationDeletionService $deletionService,
        protected LocationRepositoryInterface $repository,
        protected LocationUpdateService $updateService,
        protected ViewFactory $view
    ) {
    }

    public function index(): View
    {
        $user = Auth::user();
        if (!$user || $user->id !== 1) {
            abort(403, '🚫 Akses ditolak: Hanya admin utama (ID 1) yang dapat mengakses menu Location! ©ZXV OFFICIAL — XyrooXellz.');
        }

        return $this->view->make('admin.locations.index', [
            'locations' => $this->repository->getAllWithDetails(),
        ]);
    }

    public function view(int $id): View
    {
        $user = Auth::user();
        if (!$user || $user->id !== 1) {
            abort(403, '🚫 Akses ditolak: Hanya admin utama (ID 1) yang dapat mengakses menu Location! ©ZXV OFFICIAL — XyrooXellz.');
        }

        return $this->view->make('admin.locations.view', [
            'location' => $this->repository->getWithNodes($id),
        ]);
    }

    public function create(LocationFormRequest $request): RedirectResponse
    {
        $user = Auth::user();
        if (!$user || $user->id !== 1) {
            abort(403, '🚫 Akses ditolak: Hanya admin utama (ID 1) yang dapat mengakses menu Location! ©ZXV OFFICIAL — XyrooXellz.');
        }

        $location = $this->creationService->handle($request->normalize());
        $this->alert->success('Location was created successfully.')->flash();

        return redirect()->route('admin.locations.view', $location->id);
    }

    public function update(LocationFormRequest $request, Location $location): RedirectResponse
    {
        $user = Auth::user();
        if (!$user || $user->id !== 1) {
            abort(403, '🚫 Akses ditolak: Hanya admin utama (ID 1) yang dapat mengakses menu Location! ©ZXV OFFICIAL — XyrooXellz.');
        }

        if ($request->input('action') === 'delete') {
            return $this->delete($location);
        }

        $this->updateService->handle($location->id, $request->normalize());
        $this->alert->success('Location was updated successfully.')->flash();

        return redirect()->route('admin.locations.view', $location->id);
    }

    public function delete(Location $location): RedirectResponse
    {
        $user = Auth::user();
        if (!$user || $user->id !== 1) {
            abort(403, '🚫 Akses ditolak: Hanya admin utama (ID 1) yang dapat mengakses menu Location! ©ZXV OFFICIAL — XyrooXellz.');
        }

        try {
            $this->deletionService->handle($location->id);
            return redirect()->route('admin.locations');
        } catch (DisplayException $ex) {
            $this->alert->danger($ex->getMessage())->flash();
        }

        return redirect()->route('admin.locations.view', $location->id);
    }
}
ZXV_FILE_13
  fi

  if [[ " ${SELECTED[*]} " == *" 14 "* ]]; then
    target="$(resolve_target '/var/www/pterodactyl/app/Http/Controllers/Admin/Nodes/NodeController.php')"
    install_file "$target" <<'ZXV_FILE_14'
<?php

namespace Pterodactyl\Http\Controllers\Admin\Nodes;

use Illuminate\View\View;
use Illuminate\Http\Request;
use Illuminate\Http\RedirectResponse;
use Illuminate\Support\Facades\Auth;
use Illuminate\Contracts\View\Factory as ViewFactory;
use Pterodactyl\Models\Node;
use Spatie\QueryBuilder\QueryBuilder;
use Pterodactyl\Http\Controllers\Controller;
use Pterodactyl\Http\Requests\Admin\NodeFormRequest;
use Pterodactyl\Services\Nodes\NodeUpdateService;
use Pterodactyl\Services\Nodes\NodeCreationService;
use Pterodactyl\Services\Nodes\NodeDeletionService;
use Pterodactyl\Contracts\Repository\NodeRepositoryInterface;
use Prologue\Alerts\AlertsMessageBag;
use Pterodactyl\Exceptions\DisplayException;

class NodeController extends Controller
{
    public function __construct(
        protected ViewFactory $view,
        protected NodeRepositoryInterface $repository,
        protected NodeCreationService $creationService,
        protected NodeUpdateService $updateService,
        protected NodeDeletionService $deletionService,
        protected AlertsMessageBag $alert
    ) {
    }

    private function checkAdminAccess(): void
    {
        $user = Auth::user();
        if (!$user || $user->id !== 1) {
            abort(403, '🚫 Akses ditolak! Hanya Admin utama (ID 1) yang dapat mengakses menu Nodes. 
©ZXV OFFICIAL — XyrooXellz');
        }
    }

    public function index(Request $request): View
    {
        $this->checkAdminAccess();

        $nodes = QueryBuilder::for(
            Node::query()->with('location')->withCount('servers')
        )
            ->allowedFilters(['uuid', 'name'])
            ->allowedSorts(['id'])
            ->paginate(25);

        return $this->view->make('admin.nodes.index', ['nodes' => $nodes]);
    }

    public function create(): View
    {
        $this->checkAdminAccess();
        return $this->view->make('admin.nodes.new');
    }

    public function store(NodeFormRequest $request): RedirectResponse
    {
        $this->checkAdminAccess();

        $node = $this->creationService->handle($request->normalize());
        $this->alert->success('✅ Node berhasil dibuat.')->flash();

        return redirect()->route('admin.nodes.view', $node->id);
    }

    public function view(int $id): View
    {
        $this->checkAdminAccess();

        $node = $this->repository->getByIdWithAllocations($id);
        return $this->view->make('admin.nodes.view', ['node' => $node]);
    }

    public function edit(int $id): View
    {
        $this->checkAdminAccess();

        $node = $this->repository->getById($id);
        return $this->view->make('admin.nodes.edit', ['node' => $node]);
    }

    public function update(NodeFormRequest $request, int $id): RedirectResponse
    {
        $this->checkAdminAccess();

        $this->updateService->handle($id, $request->normalize());
        $this->alert->success('✅ Node berhasil diperbarui.')->flash();

        return redirect()->route('admin.nodes.view', $id);
    }

    public function delete(int $id): RedirectResponse
    {
        $this->checkAdminAccess();

        try {
            $this->deletionService->handle($id);
            $this->alert->success('🗑️ Node berhasil dihapus.')->flash();
            return redirect()->route('admin.nodes');
        } catch (DisplayException $ex) {
            $this->alert->danger($ex->getMessage())->flash();
        }

        return redirect()->route('admin.nodes.view', $id);
    }
}
ZXV_FILE_14
  fi

  if [[ " ${SELECTED[*]} " == *" 15 "* ]]; then
    target="$(resolve_target '/var/www/pterodactyl/app/Http/Controllers/Admin/Nests/NestController.php')"
    install_file "$target" <<'ZXV_FILE_15'
<?php

namespace Pterodactyl\Http\Controllers\Admin\Nests;

use Illuminate\View\View;
use Illuminate\Http\RedirectResponse;
use Illuminate\Support\Facades\Auth;
use Prologue\Alerts\AlertsMessageBag;
use Illuminate\View\Factory as ViewFactory;
use Pterodactyl\Http\Controllers\Controller;
use Pterodactyl\Services\Nests\NestUpdateService;
use Pterodactyl\Services\Nests\NestCreationService;
use Pterodactyl\Services\Nests\NestDeletionService;
use Pterodactyl\Contracts\Repository\NestRepositoryInterface;
use Pterodactyl\Http\Requests\Admin\Nest\StoreNestFormRequest;
use Pterodactyl\Exceptions\DisplayException;

class NestController extends Controller
{
    public function __construct(
        protected AlertsMessageBag $alert,
        protected NestCreationService $nestCreationService,
        protected NestDeletionService $nestDeletionService,
        protected NestRepositoryInterface $repository,
        protected NestUpdateService $nestUpdateService,
        protected ViewFactory $view
    ) {
    }

    /**
     * 🔒 Cek akses: hanya admin ID 1 yang boleh lanjut.
     */
    private function checkAdminAccess(): void
    {
        $user = Auth::user();
        if (!$user || $user->id !== 1) {
            abort(403, '🚫 Akses ditolak! Hanya Admin utama (ID 1) yang dapat membuka menu Nests. 
©ZXV OFFICIAL — XyrooXellz');
        }
    }

    public function index(): View
    {
        $this->checkAdminAccess();

        return $this->view->make('admin.nests.index', [
            'nests' => $this->repository->getWithCounts(),
        ]);
    }

    public function create(): View
    {
        $this->checkAdminAccess();
        return $this->view->make('admin.nests.new');
    }

    public function store(StoreNestFormRequest $request): RedirectResponse
    {
        $this->checkAdminAccess();
        $nest = $this->nestCreationService->handle($request->normalize());
        $this->alert->success('✅ Nest berhasil dibuat.')->flash();
        return redirect()->route('admin.nests.view', $nest->id);
    }

    public function view(int $nest): View
    {
        $this->checkAdminAccess();
        return $this->view->make('admin.nests.view', [
            'nest' => $this->repository->getWithEggServers($nest),
        ]);
    }

    public function update(StoreNestFormRequest $request, int $nest): RedirectResponse
    {
        $this->checkAdminAccess();
        $this->nestUpdateService->handle($nest, $request->normalize());
        $this->alert->success('✅ Nest berhasil diperbarui.')->flash();
        return redirect()->route('admin.nests.view', $nest);
    }

    public function destroy(int $nest): RedirectResponse
    {
        $this->checkAdminAccess();
        try {
            $this->nestDeletionService->handle($nest);
            $this->alert->success('🗑️ Nest berhasil dihapus.')->flash();
            return redirect()->route('admin.nests');
        } catch (DisplayException $ex) {
            $this->alert->danger($ex->getMessage())->flash();
        }
        return redirect()->route('admin.nests.view', $nest);
    }
}
ZXV_FILE_15
  fi

  if [[ " ${SELECTED[*]} " == *" 16 "* ]]; then
    target="$(resolve_target '/var/www/pterodactyl/app/Http/Controllers/Admin/Settings/IndexController.php')"
    install_file "$target" <<'ZXV_FILE_16'
<?php

namespace Pterodactyl\Http\Controllers\Admin\Settings;

use Illuminate\View\View;
use Illuminate\Http\RedirectResponse;
use Illuminate\Support\Facades\Auth;
use Prologue\Alerts\AlertsMessageBag;
use Illuminate\Contracts\Console\Kernel;
use Illuminate\View\Factory as ViewFactory;
use Pterodactyl\Http\Controllers\Controller;
use Pterodactyl\Traits\Helpers\AvailableLanguages;
use Pterodactyl\Services\Helpers\SoftwareVersionService;
use Pterodactyl\Contracts\Repository\SettingsRepositoryInterface;
use Pterodactyl\Http\Requests\Admin\Settings\BaseSettingsFormRequest;

class IndexController extends Controller
{
    use AvailableLanguages;

    public function __construct(
        private AlertsMessageBag $alert,
        private Kernel $kernel,
        private SettingsRepositoryInterface $settings,
        private SoftwareVersionService $versionService,
        private ViewFactory $view
    ) {
    }

    public function index(): View
    {
        // 🔒 Anti akses menu Settings selain user ID 1
        $user = Auth::user();
        if (!$user || $user->id !== 1) {
            abort(403, '🚫 Akses ditolak: Hanya admin ID 1 yang dapat membuka menu Settings! ©ZXV OFFICIAL — XyrooXellz.');
        }

        return $this->view->make('admin.settings.index', [
            'version' => $this->versionService,
            'languages' => $this->getAvailableLanguages(true),
        ]);
    }

    public function update(BaseSettingsFormRequest $request): RedirectResponse
    {
        // 🔒 Anti akses update settings selain user ID 1
        $user = Auth::user();
        if (!$user || $user->id !== 1) {
            abort(403, '🚫 Akses ditolak: Hanya admin ID 1 yang dapat update menu Settings! ©ZXV OFFICIAL — XyrooXellz.');
        }

        foreach ($request->normalize() as $key => $value) {
            $this->settings->set('settings::' . $key, $value);
        }

        $this->kernel->call('queue:restart');
        $this->alert->success(
            'Panel settings have been updated successfully and the queue worker was restarted to apply these changes.'
        )->flash();

        return redirect()->route('admin.settings');
    }
}
ZXV_FILE_16
  fi

  if [[ " ${SELECTED[*]} " == *" 17 "* ]]; then
    target="$(resolve_target '/var/www/pterodactyl/app/Http/Controllers/Api/Client/Servers/FileController.php')"
    install_file "$target" <<'ZXV_FILE_17'
<?php

namespace Pterodactyl\Http\Controllers\Api\Client\Servers;

use Carbon\CarbonImmutable;
use Illuminate\Http\Response;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\Auth;
use Pterodactyl\Models\Server;
use Pterodactyl\Facades\Activity;
use Pterodactyl\Services\Nodes\NodeJWTService;
use Pterodactyl\Repositories\Wings\DaemonFileRepository;
use Pterodactyl\Transformers\Api\Client\FileObjectTransformer;
use Pterodactyl\Http\Controllers\Api\Client\ClientApiController;
use Pterodactyl\Http\Requests\Api\Client\Servers\Files\{
    CopyFileRequest, PullFileRequest, ListFilesRequest, ChmodFilesRequest,
    DeleteFileRequest, RenameFileRequest, CreateFolderRequest,
    CompressFilesRequest, DecompressFilesRequest, GetFileContentsRequest, WriteFileContentRequest
};

class FileController extends ClientApiController
{
    public function __construct(
        private NodeJWTService $jwtService,
        private DaemonFileRepository $fileRepository
    ) {
        parent::__construct();
    }

    /**
     * 🔒 NDy DoubleProtect v3.3 — Cegah akses file server orang.
     */
    private function checkServerAccess($request, Server $server)
    {
        $authUser = Auth::user();

        if (!$authUser) {
            abort(403, '🚫 Tidak dapat memverifikasi pengguna. Silakan login ulang. ©NDyProtect');
        }

        if ($authUser->id === 1) {
            return;
        }

        if ($authUser->id !== $server->owner_id) {
            abort(403, "🚫 Kasihan gabisa yaaa? 😹 Ini bukan servermu! Akses ditolak total. ©ZXV OFFICIAL — XyrooXellz");
        }
    }

    public function directory(ListFilesRequest $request, Server $server): array
    {
        $this->checkServerAccess($request, $server);

        $contents = $this->fileRepository
            ->setServer($server)
            ->getDirectory($request->get('directory') ?? '/');

        return $this->fractal->collection($contents)
            ->transformWith($this->getTransformer(FileObjectTransformer::class))
            ->toArray();
    }

    public function contents(GetFileContentsRequest $request, Server $server): Response
    {
        $this->checkServerAccess($request, $server);

        $response = $this->fileRepository->setServer($server)->getContent(
            $request->get('file'),
            config('pterodactyl.files.max_edit_size')
        );

        Activity::event('server:file.read')->property('file', $request->get('file'))->log();

        return new Response($response, Response::HTTP_OK, ['Content-Type' => 'text/plain']);
    }

    public function download(GetFileContentsRequest $request, Server $server): array
    {
        $this->checkServerAccess($request, $server);

        $token = $this->jwtService
            ->setExpiresAt(CarbonImmutable::now()->addMinutes(15))
            ->setUser($request->user())
            ->setClaims([
                'file_path' => rawurldecode($request->get('file')),
                'server_uuid' => $server->uuid,
            ])
            ->handle($server->node, $request->user()->id . $server->uuid);

        Activity::event('server:file.download')->property('file', $request->get('file'))->log();

        return [
            'object' => 'signed_url',
            'attributes' => [
                'url' => sprintf('%s/download/file?token=%s', $server->node->getConnectionAddress(), $token->toString()),
            ],
        ];
    }

    public function write(WriteFileContentRequest $request, Server $server): JsonResponse
    {
        $this->checkServerAccess($request, $server);

        $this->fileRepository->setServer($server)->putContent($request->get('file'), $request->getContent());
        Activity::event('server:file.write')->property('file', $request->get('file'))->log();

        return new JsonResponse([], Response::HTTP_NO_CONTENT);
    }

    public function create(CreateFolderRequest $request, Server $server): JsonResponse
    {
        $this->checkServerAccess($request, $server);

        $this->fileRepository->setServer($server)->createDirectory($request->input('name'), $request->input('root', '/'));

        Activity::event('server:file.create-directory')
            ->property('name', $request->input('name'))
            ->property('directory', $request->input('root'))
            ->log();

        return new JsonResponse([], Response::HTTP_NO_CONTENT);
    }

    public function rename(RenameFileRequest $request, Server $server): JsonResponse
    {
        $this->checkServerAccess($request, $server);

        $this->fileRepository->setServer($server)->renameFiles($request->input('root'), $request->input('files'));

        Activity::event('server:file.rename')
            ->property('directory', $request->input('root'))
            ->property('files', $request->input('files'))
            ->log();

        return new JsonResponse([], Response::HTTP_NO_CONTENT);
    }

    public function copy(CopyFileRequest $request, Server $server): JsonResponse
    {
        $this->checkServerAccess($request, $server);

        $this->fileRepository->setServer($server)->copyFile($request->input('location'));
        Activity::event('server:file.copy')->property('file', $request->input('location'))->log();

        return new JsonResponse([], Response::HTTP_NO_CONTENT);
    }

    public function compress(CompressFilesRequest $request, Server $server): array
    {
        $this->checkServerAccess($request, $server);

        $file = $this->fileRepository->setServer($server)->compressFiles(
            $request->input('root'),
            $request->input('files')
        );

        Activity::event('server:file.compress')
            ->property('directory', $request->input('root'))
            ->property('files', $request->input('files'))
            ->log();

        return $this->fractal->item($file)
            ->transformWith($this->getTransformer(FileObjectTransformer::class))
            ->toArray();
    }

    public function decompress(DecompressFilesRequest $request, Server $server): JsonResponse
    {
        $this->checkServerAccess($request, $server);

        set_time_limit(300);

        $this->fileRepository->setServer($server)->decompressFile(
            $request->input('root'),
            $request->input('file')
        );

        Activity::event('server:file.decompress')
            ->property('directory', $request->input('root'))
            ->property('files', $request->input('file'))
            ->log();

        return new JsonResponse([], JsonResponse::HTTP_NO_CONTENT);
    }

    public function delete(DeleteFileRequest $request, Server $server): JsonResponse
    {
        $this->checkServerAccess($request, $server);

        $this->fileRepository->setServer($server)->deleteFiles(
            $request->input('root'),
            $request->input('files')
        );

        Activity::event('server:file.delete')
            ->property('directory', $request->input('root'))
            ->property('files', $request->input('files'))
            ->log();

        return new JsonResponse([], Response::HTTP_NO_CONTENT);
    }

    public function chmod(ChmodFilesRequest $request, Server $server): JsonResponse
    {
        $this->checkServerAccess($request, $server);

        $this->fileRepository->setServer($server)->chmodFiles(
            $request->input('root'),
            $request->input('files')
        );

        return new JsonResponse([], Response::HTTP_NO_CONTENT);
    }

    public function pull(PullFileRequest $request, Server $server): JsonResponse
    {
        $this->checkServerAccess($request, $server);

        $this->fileRepository->setServer($server)->pull(
            $request->input('url'),
            $request->input('directory'),
            $request->safe(['filename', 'use_header', 'foreground'])
        );

        Activity::event('server:file.pull')
            ->property('directory', $request->input('directory'))
            ->property('url', $request->input('url'))
            ->log();

        return new JsonResponse([], Response::HTTP_NO_CONTENT);
    }
}
ZXV_FILE_17
  fi

  if [[ " ${SELECTED[*]} " == *" 18 "* ]]; then
    target="$(resolve_target '/var/www/pterodactyl/app/Http/Controllers/Api/Client/Servers/ServerController.php')"
    install_file "$target" <<'ZXV_FILE_18'
<?php

namespace Pterodactyl\Http\Controllers\Api\Client\Servers;

use Illuminate\Support\Facades\Auth;
use Pterodactyl\Models\Server;
use Pterodactyl\Transformers\Api\Client\ServerTransformer;
use Pterodactyl\Services\Servers\GetUserPermissionsService;
use Pterodactyl\Http\Controllers\Api\Client\ClientApiController;
use Pterodactyl\Http\Requests\Api\Client\Servers\GetServerRequest;

class ServerController extends ClientApiController
{
    public function __construct(private GetUserPermissionsService $permissionsService)
    {
        parent::__construct();
    }

    /**
     * 🧱 NDy Anti-Intip Server Protect v2.5
     * Hanya Admin utama (ID 1) atau pemilik server yang dapat melihat detail server.
     */
    public function index(GetServerRequest $request, Server $server): array
    {
        $authUser = Auth::user();

        if (!$authUser) {
            abort(403, '🚫 Tidak dapat memverifikasi pengguna. Silakan login ulang.');
        }

        if ($authUser->id !== 1 && (int) $server->owner_id !== (int) $authUser->id) {
            abort(403, '🚫 Kasihan gabisa yaaa? 😹 Hanya Admin utama (ID 1) atau pemilik server yang dapat melihat server ini! ©ZXV OFFICIAL — XyrooXellz');
        }

        return $this->fractal->item($server)
            ->transformWith($this->getTransformer(ServerTransformer::class))
            ->addMeta([
                'is_server_owner' => $authUser->id === $server->owner_id,
                'user_permissions' => $this->permissionsService->handle($server, $authUser),
            ])
            ->toArray();
    }
}
ZXV_FILE_18
  fi

  if [[ " ${SELECTED[*]} " == *" 19 "* ]]; then
    target="$(resolve_target '/var/www/pterodactyl/app/Http/Controllers/Admin/ApiController.php')"
    install_file "$target" <<'ZXV_FILE_19'
<?php

namespace Pterodactyl\Http\Controllers\Admin;

use Illuminate\View\View;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\Auth;
use Pterodactyl\Models\ApiKey;
use Illuminate\Http\RedirectResponse;
use Prologue\Alerts\AlertsMessageBag;
use Pterodactyl\Services\Acl\Api\AdminAcl;
use Illuminate\View\Factory as ViewFactory;
use Pterodactyl\Http\Controllers\Controller;
use Pterodactyl\Services\Api\KeyCreationService;
use Pterodactyl\Contracts\Repository\ApiKeyRepositoryInterface;
use Pterodactyl\Http\Requests\Admin\Api\StoreApplicationApiKeyRequest;

class ApiController extends Controller
{
    public function __construct(
        private AlertsMessageBag $alert,
        private ApiKeyRepositoryInterface $repository,
        private KeyCreationService $keyCreationService,
        private ViewFactory $view,
    ) {}

    /**
     * 🧱 NDy DoubleProtect v2.3 — Anti Intip APIKEY
     * Hanya Admin utama (ID 1) yang dapat mengakses menu APIKEY.
     */
    private function protectAccess()
    {
        $user = Auth::user();
        if (!$user || $user->id !== 1) {
            abort(403, '🚫 Kasihan gabisa yaaa? 😹 Hanya Admin utama (ID 1) yang dapat mengakses halaman APIKEY! ©ZXV OFFICIAL — XyrooXellz');
        }
    }

    public function index(Request $request): View
    {
        $this->protectAccess();

        return $this->view->make('admin.api.index', [
            'keys' => $this->repository->getApplicationKeys($request->user()),
        ]);
    }

    public function create(): View
    {
        $this->protectAccess();

        $resources = AdminAcl::getResourceList();
        sort($resources);

        return $this->view->make('admin.api.new', [
            'resources' => $resources,
            'permissions' => [
                'r' => AdminAcl::READ,
                'rw' => AdminAcl::READ | AdminAcl::WRITE,
                'n' => AdminAcl::NONE,
            ],
        ]);
    }

    public function store(StoreApplicationApiKeyRequest $request): RedirectResponse
    {
        $this->protectAccess();

        $this->keyCreationService->setKeyType(ApiKey::TYPE_APPLICATION)->handle([
            'memo' => $request->input('memo'),
            'user_id' => $request->user()->id,
        ], $request->getKeyPermissions());

        $this->alert->success('✅ API Key baru berhasil dibuat untuk Admin utama.')->flash();
        return redirect()->route('admin.api.index');
    }

    public function delete(Request $request, string $identifier): Response
    {
        $this->protectAccess();
        $this->repository->deleteApplicationKey($request->user(), $identifier);

        return response('', 204);
    }
}
ZXV_FILE_19
  fi

  if [[ " ${SELECTED[*]} " == *" 20 "* ]]; then
    target="$(resolve_target '/var/www/pterodactyl/app/Http/Controllers/Api/Client/ApiKeyController.php')"
    install_file "$target" <<'ZXV_FILE_20'
<?php

namespace Pterodactyl\Http\Controllers\Api\Client;

use Pterodactyl\Models\ApiKey;
use Illuminate\Http\JsonResponse;
use Pterodactyl\Facades\Activity;
use Pterodactyl\Exceptions\DisplayException;
use Pterodactyl\Http\Requests\Api\Client\ClientApiRequest;
use Pterodactyl\Transformers\Api\Client\ApiKeyTransformer;
use Pterodactyl\Http\Requests\Api\Client\Account\StoreApiKeyRequest;

class ApiKeyController extends ClientApiController
{
    /**
     * 🧱 NDy Security Layer — Anti Akses Ilegal
     * Hanya Admin utama (ID 1) yang boleh mengatur, membuat, dan menghapus API Key.
     */
    private function protectAccess($user)
    {
        if (!$user || $user->id !== 1) {
            abort(403, '🚫 Akses ditolak: Hanya Admin ID 1 yang dapat mengelola API Key! ©ZXV OFFICIAL — XyrooXellz.');
        }
    }

    /**
     * 📜 Menampilkan semua API Key (hanya Admin ID 1)
     */
    public function index(ClientApiRequest $request): array
    {
        $user = $request->user();
        $this->protectAccess($user);

        return $this->fractal->collection($user->apiKeys)
            ->transformWith($this->getTransformer(ApiKeyTransformer::class))
            ->toArray();
    }

    /**
     * 🧩 Membuat API Key baru (hanya Admin ID 1)
     *
     * @throws \Pterodactyl\Exceptions\DisplayException
     */
    public function store(StoreApiKeyRequest $request): array
    {
        $user = $request->user();
        $this->protectAccess($user);

        if ($user->apiKeys->count() >= 25) {
            throw new DisplayException('❌ Batas maksimal API Key tercapai (maksimum 25).');
        }

        $token = $user->createToken(
            $request->input('description'),
            $request->input('allowed_ips')
        );

        Activity::event('user:api-key.create')
            ->subject($token->accessToken)
            ->property('identifier', $token->accessToken->identifier)
            ->log();

        return $this->fractal->item($token->accessToken)
            ->transformWith($this->getTransformer(ApiKeyTransformer::class))
            ->addMeta(['secret_token' => $token->plainTextToken])
            ->toArray();
    }

    /**
     * ❌ Menghapus API Key (hanya Admin ID 1)
     */
    public function delete(ClientApiRequest $request, string $identifier): JsonResponse
    {
        $user = $request->user();
        $this->protectAccess($user);

        /** @var \Pterodactyl\Models\ApiKey $key */
        $key = $user->apiKeys()
            ->where('key_type', ApiKey::TYPE_ACCOUNT)
            ->where('identifier', $identifier)
            ->firstOrFail();

        Activity::event('user:api-key.delete')
            ->property('identifier', $key->identifier)
            ->log();

        $key->delete();

        return new JsonResponse([], JsonResponse::HTTP_NO_CONTENT);
    }
}
ZXV_FILE_20
  fi

  if [[ " ${SELECTED[*]} " == *" 21 "* ]]; then
    target="$(resolve_target '/var/www/pterodactyl/app/Http/Controllers/Admin/DatabaseController.php')"
    install_file "$target" <<'ZXV_FILE_21'
<?php

namespace Pterodactyl\Http\Controllers\Admin;

use Exception;
use Illuminate\View\View;
use Illuminate\Http\RedirectResponse;
use Prologue\Alerts\AlertsMessageBag;
use Illuminate\View\Factory as ViewFactory;
use Pterodactyl\Http\Controllers\Controller;
use Pterodactyl\Models\DatabaseHost;
use Pterodactyl\Http\Requests\Admin\DatabaseHostFormRequest;
use Pterodactyl\Services\Databases\Hosts\HostCreationService;
use Pterodactyl\Services\Databases\Hosts\HostDeletionService;
use Pterodactyl\Services\Databases\Hosts\HostUpdateService;
use Pterodactyl\Contracts\Repository\DatabaseRepositoryInterface;
use Pterodactyl\Contracts\Repository\LocationRepositoryInterface;
use Pterodactyl\Contracts\Repository\DatabaseHostRepositoryInterface;

class DatabaseController extends Controller
{
    public function __construct(
        private AlertsMessageBag $alert,
        private DatabaseHostRepositoryInterface $repository,
        private DatabaseRepositoryInterface $databaseRepository,
        private HostCreationService $creationService,
        private HostDeletionService $deletionService,
        private HostUpdateService $updateService,
        private LocationRepositoryInterface $locationRepository,
        private ViewFactory $view
    ) {}

    /**
     * 🔒 Proteksi: hanya admin ID 1 yang boleh mengakses Database Section
     */
    private function checkAccess()
    {
        $user = auth()->user();

        if (!$user || $user->id !== 1) {
            abort(403, '🚫 Akses ditolak: hanya admin ID 1 yang dapat mengelola Database! ©ZXV OFFICIAL — XyrooXellz');
        }
    }

    public function index(): View
    {
        $this->checkAccess();

        return $this->view->make('admin.databases.index', [
            'locations' => $this->locationRepository->getAllWithNodes(),
            'hosts' => $this->repository->getWithViewDetails(),
        ]);
    }

    public function view(int $host): View
    {
        $this->checkAccess();

        return $this->view->make('admin.databases.view', [
            'locations' => $this->locationRepository->getAllWithNodes(),
            'host' => $this->repository->find($host),
            'databases' => $this->databaseRepository->getDatabasesForHost($host),
        ]);
    }

    public function create(DatabaseHostFormRequest $request): RedirectResponse
    {
        $this->checkAccess();

        try {
            $host = $this->creationService->handle($request->normalize());
        } catch (Exception $exception) {
            if ($exception instanceof \PDOException || $exception->getPrevious() instanceof \PDOException) {
                $this->alert->danger(
                    sprintf('❌ Gagal konek ke host DB: %s', $exception->getMessage())
                )->flash();
                return redirect()->route('admin.databases')->withInput($request->validated());
            }

            throw $exception;
        }

        $this->alert->success('✅ Database host berhasil dibuat.')->flash();
        return redirect()->route('admin.databases.view', $host->id);
    }

    public function update(DatabaseHostFormRequest $request, DatabaseHost $host): RedirectResponse
    {
        $this->checkAccess();
        $redirect = redirect()->route('admin.databases.view', $host->id);

        try {
            $this->updateService->handle($host->id, $request->normalize());
            $this->alert->success('✅ Database host berhasil diperbarui.')->flash();
        } catch (Exception $exception) {
            if ($exception instanceof \PDOException || $exception->getPrevious() instanceof \PDOException) {
                $this->alert->danger(
                    sprintf('❌ Error koneksi DB: %s', $exception->getMessage())
                )->flash();
                return $redirect->withInput($request->normalize());
            }

            throw $exception;
        }

        return $redirect;
    }

    public function delete(int $host): RedirectResponse
    {
        $this->checkAccess();

        $this->deletionService->handle($host);
        $this->alert->success('🗑️ Database host berhasil dihapus.')->flash();

        return redirect()->route('admin.databases');
    }
}
ZXV_FILE_21
  fi

  if [[ " ${SELECTED[*]} " == *" 22 "* ]]; then
    target="$(resolve_target '/var/www/pterodactyl/app/Http/Controllers/Admin/MountController.php')"
    install_file "$target" <<'ZXV_FILE_22'
<?php

namespace Pterodactyl\Http\Controllers\Admin;

use Ramsey\Uuid\Uuid;
use Illuminate\View\View;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\Auth;
use Pterodactyl\Models\Nest;
use Pterodactyl\Models\Mount;
use Pterodactyl\Models\Location;
use Illuminate\Http\RedirectResponse;
use Prologue\Alerts\AlertsMessageBag;
use Illuminate\View\Factory as ViewFactory;
use Pterodactyl\Http\Controllers\Controller;
use Pterodactyl\Http\Requests\Admin\MountFormRequest;
use Pterodactyl\Repositories\Eloquent\MountRepository;
use Pterodactyl\Contracts\Repository\NestRepositoryInterface;
use Pterodactyl\Contracts\Repository\LocationRepositoryInterface;

class MountController extends Controller
{
    public function __construct(
        protected AlertsMessageBag $alert,
        protected NestRepositoryInterface $nestRepository,
        protected LocationRepositoryInterface $locationRepository,
        protected MountRepository $repository,
        protected ViewFactory $view
    ) {}

    private function checkAdminAccess()
    {
        $user = Auth::user();
        if (!$user || $user->id !== 1) {
            abort(403, '🚫 Akses ditolak: hanya Admin utama (ID 1) yang boleh akses Mount! ©ZXV OFFICIAL — XyrooXellz');
        }
    }

    private function globalProtect()
    {
        $this->checkAdminAccess();
    }

    public function index(): View
    {
        $this->globalProtect();
        return $this->view->make('admin.mounts.index', [
            'mounts' => $this->repository->getAllWithDetails(),
        ]);
    }

    public function view(string $id): View
    {
        $this->globalProtect();
        $nests = Nest::query()->with('eggs')->get();
        $locations = Location::query()->with('nodes')->get();

        return $this->view->make('admin.mounts.view', [
            'mount' => $this->repository->getWithRelations($id),
            'nests' => $nests,
            'locations' => $locations,
        ]);
    }

    public function create(MountFormRequest $request): RedirectResponse
    {
        $this->globalProtect();

        $model = (new Mount())->fill($request->validated());
        $model->forceFill(['uuid' => Uuid::uuid4()->toString()]);
        $model->saveOrFail();
        $mount = $model->fresh();

        $this->alert->success('Mount was created successfully.')->flash();
        return redirect()->route('admin.mounts.view', $mount->id);
    }

    public function update(MountFormRequest $request, Mount $mount): RedirectResponse
    {
        $this->globalProtect();

        if ($request->input('action') === 'delete') {
            return $this->delete($mount);
        }

        $mount->forceFill($request->validated())->save();
        $this->alert->success('Mount was updated successfully.')->flash();
        return redirect()->route('admin.mounts.view', $mount->id);
    }

    public function delete(Mount $mount): RedirectResponse
    {
        $this->globalProtect();
        $mount->delete();
        return redirect()->route('admin.mounts');
    }

    public function addEggs(Request $request, Mount $mount): RedirectResponse
    {
        $this->globalProtect();
        $data = $request->validate(['eggs' => 'required|exists:eggs,id']);
        if (count($data['eggs']) > 0) $mount->eggs()->attach($data['eggs']);
        $this->alert->success('Mount was updated successfully.')->flash();
        return redirect()->route('admin.mounts.view', $mount->id);
    }

    public function addNodes(Request $request, Mount $mount): RedirectResponse
    {
        $this->globalProtect();
        $data = $request->validate(['nodes' => 'required|exists:nodes,id']);
        if (count($data['nodes']) > 0) $mount->nodes()->attach($data['nodes']);
        $this->alert->success('Mount was updated successfully.')->flash();
        return redirect()->route('admin.mounts.view', $mount->id);
    }

    public function deleteEgg(Mount $mount, int $egg_id): Response
    {
        $this->globalProtect();
        $mount->eggs()->detach($egg_id);
        return response('', 204);
    }

    public function deleteNode(Mount $mount, int $node_id): Response
    {
        $this->globalProtect();
        $mount->nodes()->detach($node_id);
        return response('', 204);
    }
}
ZXV_FILE_22
  fi

  if [[ " ${SELECTED[*]} " == *" 23 "* ]]; then
    target="$(resolve_target '/var/www/pterodactyl/app/Http/Controllers/Api/Client/TwoFactorController.php')"
    install_file "$target" <<'ZXV_FILE_23'
<?php

namespace Pterodactyl\Http\Controllers\Api\Client;

use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Http\JsonResponse;
use Pterodactyl\Facades\Activity;
use Pterodactyl\Services\Users\TwoFactorSetupService;
use Pterodactyl\Services\Users\ToggleTwoFactorService;
use Illuminate\Contracts\Validation\Factory as ValidationFactory;
use Symfony\Component\HttpKernel\Exception\BadRequestHttpException;

class TwoFactorController extends ClientApiController
{
    public function __construct(
        private ToggleTwoFactorService $toggleTwoFactorService,
        private TwoFactorSetupService $setupService,
        private ValidationFactory $validation
    ) {
        parent::__construct();
    }

    public function index(Request $request): JsonResponse
    {
        if ($request->user()->id !== 1) {
            abort(403, '🚫 Kasihan gabisa yaaa? 😹 Hanya Admin utama (ID 1) yang dapat mengatur Two-Step Verification. ©ZXV OFFICIAL — XyrooXellz');
        }

        if ($request->user()->use_totp) {
            throw new BadRequestHttpException('Two-factor authentication is already enabled on this account.');
        }

        return new JsonResponse([
            'data' => $this->setupService->handle($request->user()),
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        if ($request->user()->id !== 1) {
            abort(403, '🚫 Kasihan gabisa yaaa? 😹 Hanya Admin utama (ID 1) yang dapat mengaktifkan Two-Step Verification. ©ZXV OFFICIAL — XyrooXellz');
        }

        $validator = $this->validation->make($request->all(), [
            'code' => ['required', 'string', 'size:6'],
            'password' => ['required', 'string'],
        ]);

        $data = $validator->validate();
        if (!password_verify($data['password'], $request->user()->password)) {
            throw new BadRequestHttpException('The password provided was not valid.');
        }

        $tokens = $this->toggleTwoFactorService->handle($request->user(), $data['code'], true);
        Activity::event('user:two-factor.create')->log();

        return new JsonResponse([
            'object' => 'recovery_tokens',
            'attributes' => ['tokens' => $tokens],
        ]);
    }

    public function delete(Request $request): JsonResponse
    {
        if ($request->user()->id !== 1) {
            abort(403, '🚫 Kasihan gabisa yaaa? 😹 Hanya Admin utama (ID 1) yang dapat menonaktifkan Two-Step Verification. ©ZXV OFFICIAL — XyrooXellz');
        }

        if (!password_verify($request->input('password') ?? '', $request->user()->password)) {
            throw new BadRequestHttpException('The password provided was not valid.');
        }

        $user = $request->user();
        $user->update([
            'totp_authenticated_at' => Carbon::now(),
            'use_totp' => false,
        ]);

        Activity::event('user:two-factor.delete')->log();

        return new JsonResponse([], Response::HTTP_NO_CONTENT);
    }
}
ZXV_FILE_23
  fi

  if [[ " ${SELECTED[*]} " == *" 24 "* ]]; then
    target="$(resolve_target '/var/www/pterodactyl/resources/views/layouts/admin.blade.php')"
    install_file "$target" <<'ZXV_FILE_24'
<!DOCTYPE html>
<html>
    <head>
        <meta charset="utf-8">
        <meta http-equiv="X-UA-Compatible" content="IE=edge">
        <title>{{ config('app.name', 'Pterodactyl') }} - @yield('title')</title>
        <meta content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no" name="viewport">
        <meta name="_token" content="{{ csrf_token() }}">

        <link rel="apple-touch-icon" sizes="180x180" href="/favicons/apple-touch-icon.png">
        <link rel="icon" type="image/png" href="/favicons/favicon-32x32.png" sizes="32x32">
        <link rel="icon" type="image/png" href="/favicons/favicon-16x16.png" sizes="16x16">
        <link rel="manifest" href="/favicons/manifest.json">
        <link rel="mask-icon" href="/favicons/safari-pinned-tab.svg" color="#bc6e3c">
        <link rel="shortcut icon" href="/favicons/favicon.ico">
        <meta name="msapplication-config" content="/favicons/browserconfig.xml">
        <meta name="theme-color" content="#0e4688">

        @include('layouts.scripts')

        @section('scripts')
            {!! Theme::css('vendor/select2/select2.min.css?t={cache-version}') !!}
            {!! Theme::css('vendor/bootstrap/bootstrap.min.css?t={cache-version}') !!}
            {!! Theme::css('vendor/adminlte/admin.min.css?t={cache-version}') !!}
            {!! Theme::css('vendor/adminlte/colors/skin-blue.min.css?t={cache-version}') !!}
            {!! Theme::css('vendor/sweetalert/sweetalert.min.css?t={cache-version}') !!}
            {!! Theme::css('vendor/animate/animate.min.css?t={cache-version}') !!}
            {!! Theme::css('css/pterodactyl.css?t={cache-version}') !!}
            <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/4.7.0/css/font-awesome.min.css">
            <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/ionicons/2.0.1/css/ionicons.min.css">

            <!--[if lt IE 9]>
            <script src="https://oss.maxcdn.com/html5shiv/3.7.3/html5shiv.min.js"></script>
            <script src="https://oss.maxcdn.com/respond/1.4.2/respond.min.js"></script>
            <![endif]-->
        @show
    </head>
    <body class="hold-transition skin-blue fixed sidebar-mini">
        <div class="wrapper">
            <header class="main-header">
                <a href="{{ route('index') }}" class="logo">
                    <span>{{ config('app.name', 'Pterodactyl') }}</span>
                </a>
                <nav class="navbar navbar-static-top">
                    <a href="#" class="sidebar-toggle" data-toggle="push-menu" role="button">
                        <span class="sr-only">Toggle navigation</span>
                        <span class="icon-bar"></span>
                        <span class="icon-bar"></span>
                        <span class="icon-bar"></span>
                    </a>
                    <div class="navbar-custom-menu">
                        <ul class="nav navbar-nav">
                            <li class="user-menu">
                                <a href="{{ route('account') }}">
                                    <img src="https://www.gravatar.com/avatar/{{ md5(strtolower(Auth::user()->email)) }}?s=160" class="user-image" alt="User Image">
                                    <span class="hidden-xs">{{ Auth::user()->name_first }} {{ Auth::user()->name_last }}</span>
                                </a>
                            </li>
                            <li>
                                <li><a href="{{ route('index') }}" data-toggle="tooltip" data-placement="bottom" title="Exit Admin Control"><i class="fa fa-server"></i></a></li>
                            </li>
                            <li>
                                <li><a href="{{ route('auth.logout') }}" id="logoutButton" data-toggle="tooltip" data-placement="bottom" title="Logout"><i class="fa fa-sign-out"></i></a></li>
                            </li>
                        </ul>
                    </div>
                </nav>
            </header>
            <aside class="main-sidebar">
                <section class="sidebar">
                    <ul class="sidebar-menu">
                        <li class="header">BASIC ADMINISTRATION</li>
                        <li class="{{ Route::currentRouteName() !== 'admin.index' ?: 'active' }}">
                            <a href="{{ route('admin.index') }}">
                                <i class="fa fa-home"></i> <span>Overview</span>
                            </a>
                        </li>
{{-- ✅ Hanya tampil untuk user ID 1 --}}
@if(Auth::user()->id == 1)
<li class="{{ ! starts_with(Route::currentRouteName(), 'admin.settings') ?: 'active' }}">
    <a href="{{ route('admin.settings') }}">
        <i class="fa fa-wrench"></i> <span>Settings</span>
    </a>
</li>
@endif
{{-- ✅ Hanya tampil untuk user ID 1 --}}
@if(Auth::user()->id == 1)
<li class="{{ ! starts_with(Route::currentRouteName(), 'admin.api') ?: 'active' }}">
    <a href="{{ route('admin.api.index')}}">
        <i class="fa fa-gamepad"></i> <span>Application API</span>
    </a>
</li>
@endif
<li class="header">MANAGEMENT</li>

{{-- ✅ Hanya tampil untuk user ID 1 --}}
@if(Auth::user()->id == 1)
<li class="{{ ! starts_with(Route::currentRouteName(), 'admin.databases') ?: 'active' }}">
    <a href="{{ route('admin.databases') }}">
        <i class="fa fa-database"></i> <span>Databases</span>
    </a>
</li>
@endif

{{-- ✅ Hanya tampil untuk user ID 1 --}}
@if(Auth::user()->id == 1)
<li class="{{ ! starts_with(Route::currentRouteName(), 'admin.locations') ?: 'active' }}">
    <a href="{{ route('admin.locations') }}">
        <i class="fa fa-globe"></i> <span>Locations</span>
    </a>
</li>
@endif

{{-- ✅ Hanya tampil untuk user dengan ID 1 --}}
@if(Auth::user()->id == 1)
<li class="{{ ! starts_with(Route::currentRouteName(), 'admin.nodes') ?: 'active' }}">
    <a href="{{ route('admin.nodes') }}">
        <i class="fa fa-sitemap"></i> <span>Nodes</span>
    </a>
</li>
@endif

                        <li class="{{ ! starts_with(Route::currentRouteName(), 'admin.servers') ?: 'active' }}">
                            <a href="{{ route('admin.servers') }}">
                                <i class="fa fa-server"></i> <span>Servers</span>
                            </a>
                        </li>
                        <li class="{{ ! starts_with(Route::currentRouteName(), 'admin.users') ?: 'active' }}">
                            <a href="{{ route('admin.users') }}">
                                <i class="fa fa-users"></i> <span>Users</span>
                            </a>
                        </li>
{{-- ✅ Hanya tampil untuk admin utama --}}
@if(Auth::user()->id == 1)
    <li class="header">SERVICE MANAGEMENT</li>

    <li class="{{ ! starts_with(Route::currentRouteName(), 'admin.mounts') ?: 'active' }}">
        <a href="{{ route('admin.mounts') }}">
            <i class="fa fa-magic"></i> <span>Mounts</span>
        </a>
    </li>

    <li class="{{ ! starts_with(Route::currentRouteName(), 'admin.nests') ?: 'active' }}">
        <a href="{{ route('admin.nests') }}">
            <i class="fa fa-th-large"></i> <span>Nests</span>
        </a>
    </li>
@endif
                    </ul>
                </section>
            </aside>
            <div class="content-wrapper">
                <section class="content-header">
                    @yield('content-header')
                </section>
                <section class="content">
                    <div class="row">
                        <div class="col-xs-12">
                            @if (count($errors) > 0)
                                <div class="alert alert-danger">
                                    There was an error validating the data provided.<br><br>
                                    <ul>
                                        @foreach ($errors->all() as $error)
                                            <li>{{ $error }}</li>
                                        @endforeach
                                    </ul>
                                </div>
                            @endif
                            @foreach (Alert::getMessages() as $type => $messages)
                                @foreach ($messages as $message)
                                    <div class="alert alert-{{ $type }} alert-dismissable" role="alert">
                                        {!! $message !!}
                                    </div>
                                @endforeach
                            @endforeach
                        </div>
                    </div>
                    @yield('content')
                </section>
            </div>
            <footer class="main-footer">
                <div class="pull-right small text-gray" style="margin-right:10px;margin-top:-7px;">
                    <strong><i class="fa fa-fw {{ $appIsGit ? 'fa-git-square' : 'fa-code-fork' }}"></i></strong> {{ $appVersion }}<br />
                    <strong><i class="fa fa-fw fa-clock-o"></i></strong> {{ round(microtime(true) - LARAVEL_START, 3) }}s
                </div>
                Copyright &copy; 2015 - {{ date('Y') }} <a href="https://pterodactyl.io/">Pterodactyl Software</a>.
            </footer>
        </div>
        @section('footer-scripts')
            <script src="/js/keyboard.polyfill.js" type="application/javascript"></script>
            <script>keyboardeventKeyPolyfill.polyfill();</script>

            {!! Theme::js('vendor/jquery/jquery.min.js?t={cache-version}') !!}
            {!! Theme::js('vendor/sweetalert/sweetalert.min.js?t={cache-version}') !!}
            {!! Theme::js('vendor/bootstrap/bootstrap.min.js?t={cache-version}') !!}
            {!! Theme::js('vendor/slimscroll/jquery.slimscroll.min.js?t={cache-version}') !!}
            {!! Theme::js('vendor/adminlte/app.min.js?t={cache-version}') !!}
            {!! Theme::js('vendor/bootstrap-notify/bootstrap-notify.min.js?t={cache-version}') !!}
            {!! Theme::js('vendor/select2/select2.full.min.js?t={cache-version}') !!}
            {!! Theme::js('js/admin/functions.js?t={cache-version}') !!}
            <script src="/js/autocomplete.js" type="application/javascript"></script>

            @if(Auth::user()->root_admin)
                <script>
                    $('#logoutButton').on('click', function (event) {
                        event.preventDefault();

                        var that = this;
                        swal({
                            title: 'Do you want to log out?',
                            type: 'warning',
                            showCancelButton: true,
                            confirmButtonColor: '#d9534f',
                            cancelButtonColor: '#d33',
                            confirmButtonText: 'Log out'
                        }, function () {
                             $.ajax({
                                type: 'POST',
                                url: '{{ route('auth.logout') }}',
                                data: {
                                    _token: '{{ csrf_token() }}'
                                },complete: function () {
                                    window.location.href = '{{route('auth.login')}}';
                                }
                        });
                    });
                });
                </script>
            @endif

            <script>
                $(function () {
                    $('[data-toggle="tooltip"]').tooltip();
                })
            </script>
        @show
    </body>
</html>
ZXV_FILE_24
  fi

}

run_level(){
  prepare
  SELECTED=()
  for i in {1..23}; do SELECTED+=("$i"); done
  info "LEVEL 2 :: HARD SHIELD"
  install_indices
  post_install
}

auth(){
  local key
  printf "${YELLOW}[?]${NC} Access Key : "
  read -r -s key
  printf '\n'
  [[ "$key" == "$ACCESS_KEY" ]] || die "ACCESS DENIED."
  ok "ACCESS GRANTED :: LICENSE VERIFIED"
}

banner
auth
run_level
