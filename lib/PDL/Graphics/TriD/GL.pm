package # hide from PAUSE
  PDL::Graphics::TriD::GL;

use strict;
use warnings;
use PDL::Graphics::TriD::Window qw();
use PDL::Options;

$PDL::Graphics::TriD::verbose //= 0;

{ package # hide from PAUSE
  PDL::Graphics::TriD::Material;
sub to_uniforms {
  my $this = shift;
  {
    uMatshininess => ['1f'=>[$this->{Shine}]],
    uMatspecular => ['4f'=>$this->{Specular}],
    uMatambient => ['4f'=>$this->{Ambient}],
    uMatdiffuse => ['4f'=>$this->{Diffuse}],
    uMatemission => ['4f'=>$this->{Emission}],
  };
}
}

{ package # hide from PAUSE
  PDL::Graphics::TriD::Object;
sub togl_setup {
  my ($this, @args) = @_;
  print "togl_setup $this\n" if $PDL::Graphics::TriD::verbose;
  $_->togl_setup(@args) for $this->contained_objects;
}
sub togl {
  $_->togl(
    UNIVERSAL::isa($_, 'PDL::Graphics::TriD::GObject') ? $_->{Points} : (),
    @_[1..$#_]
  ) for $_[0]->contained_objects
}
sub ortho {
  my (undef, $left, $right, $bottom, $top, $near, $far) = @_;
  my ($rml, $rpl, $tmb, $tpb, $fmn, $fpn) = ($right-$left, $right+$left,
    $top-$bottom, $top+$bottom, $far-$near, $far+$near);
  PDL->pdl(PDL::float, [2/$rml, 0, 0, -$rpl/$rml], [0, 2/$tmb, 0, -$tpb/$tmb],
    [0, 0, -2/$fmn, -$fpn/$fmn], [0, 0, 0, 1]);
}
# https://stackoverflow.com/questions/12943164/replacement-for-gluperspective-with-glfrustrum
sub frustum {
  my (undef, $left, $right, $bottom, $top, $near, $far) = @_;
  my ($rml, $rpl, $tmb, $tpb, $fmn, $fpn) = ($right-$left, $right+$left,
    $top-$bottom, $top+$bottom, $far-$near, $far+$near);
  PDL->pdl(PDL::float,
    [2*$near/$rml, 0, $rpl/$rml, 0],
    [0, 2*$near/$tmb, $tpb/$tmb, 0],
    [0, 0, -$fpn/$fmn, -2*$far*$near/$fmn],
    [0, 0, -1, 0]);
}
sub translate {
  my (undef, $x, $y, $z) = @_;
  PDL->pdl(PDL::float,
    [1, 0, 0, $x],
    [0, 1, 0, $y],
    [0, 0, 1, $z],
    [0, 0, 0, 1]);
}
}

{ package # hide from PAUSE
  PDL::Graphics::TriD::Graph;
sub togl_setup {
  my ($this, $points_arg, @args) = @_;
  $this->{Axis}{$_}->togl_setup($points_arg, @args) for grep $_ ne "Default", keys %{$this->{Axis}};
  while (my ($series,$h) = each %{ $this->{Data} }) {
    for my $data (values %$h) {
      $data->togl_setup($this->get_points($series, $data), @args);
    }
  }
}
sub togl {
  my ($this, @args) = @_;
  $this->{Axis}{$_}->togl(@args) for grep $_ ne "Default", keys %{$this->{Axis}};
  while (my ($series,$h) = each %{ $this->{Data} }) {
    for my $data (values %$h) {
      $data->togl($this->get_points($series, $data), @args);
    }
  }
}
}

##################################
# Graph Objects

my ($VS_IN, $VS_OUT, $FS_IN, $FS_OUT) = ('attribute', 'varying', 'varying', 'out');
my $FRAG_OUT = 'gl_FragColor';
sub _passthrough {
  my ($name, $size) = @_;
  ("vs_in_${name}_decl" => "$VS_IN vec$size $name;\n",
    "vs_out_${name}_decl" => "$VS_OUT vec$size v".ucfirst($name).";\n",
    "fs_in_${name}_decl" => "$FS_IN vec$size v".ucfirst($name).";\n",
    "vs_out_$name" => "  v".ucfirst($name)." = $name;\n")
}
my %SHADERBITS = (
version => <<'EOF',
#version 120
EOF
main_start => "void main() {\n",
main_end => "}\n",
lightfunc => <<'EOF',
/* modified from https://community.khronos.org/t/help-with-gouraud-phong-shading-in-shaders/73192/2 */
void lightfunc(
  vec4 lightpos, vec4 lightambient, vec4 lightdiffuse, vec4 lightspecular,
  vec4 matambient, vec4 matspecular, float matshininess,
  vec3 position, vec3 norm, vec4 in_diffuse,
  out vec4 ambient, out vec4 diffuse, out vec4 spec
) {
  vec3 n = normalize(norm);
  vec3 s = lightpos.w == 0.0 ? normalize(lightpos.xyz) /* Directional */
    : normalize(lightpos.xyz - position); /* Positional/Spotlight */
  vec3 v = normalize(-position);
  float sDotN = max(dot(s, n), 0.0);
  ambient = lightambient * matambient;
  diffuse = lightdiffuse * in_diffuse * sDotN;
  // Guard against negative dots and zero shininess (NVIDIA flare fix)
  if (matshininess > 0.0 && sDotN > 0.0) {
    vec3 h = normalize(s + v); // Halfway vector
    float hDotN = max(dot(h, n), 0.0);
    spec = lightspecular * matspecular * pow(hDotN, matshininess);
  } else {
    spec = vec4(0.0);
  }
}
EOF
lightfuncgouraud => <<'EOF',
vec4 lightfuncgouraud(
  vec4 lightpos, vec4 lightambient, vec4 lightdiffuse, vec4 lightspecular,
  vec4 matambient, vec4 matspecular, float matshininess,
  vec3 position, vec3 norm
) {
  vec4 ambient, diffuse, spec;
  lightfunc(
    lightpos, lightambient, lightdiffuse, lightspecular,
    matambient, matspecular, matshininess,
    position, norm, vec4(1.0), ambient, diffuse, spec
  );
  return ambient + diffuse + spec;
}
EOF
(map _passthrough(@$_), [position=>3], [normal=>3], [colour=>3], [texcoord=>2]),
fs_diffuse_colour => "  vec4 in_diffuse = vec4(vColour, 1);\n",
fs_diffuse_tex => "  vec4 in_diffuse = texture2D(tex, vTexcoord);\n",
fs_out_fragcolour_decl => "",
fs_out_flat => "  $FRAG_OUT = in_diffuse;\n",
vs_in => "  vec3 the_position = position;\n",
vs_in_offset_decl => "$VS_IN vec3 offset;\n",
vs_do_offset => "  the_position += offset;\n",
vs_out => "  gl_Position = uMVP * vec4(the_position, 1);\n",
vs_out_light => <<'EOF',
  vNormal = normalize(uNormalMatrix * normal);
  vPosition = vec3(uMV * vec4(the_position, 1));
  vLightpos = uMV * uLightposition;
EOF
fs_diffuse_material => "  vec4 in_diffuse = uMatdiffuse;\n",
fs_out_light => <<EOF,
  vec4 ambient, diffuse, spec;
  lightfunc(
    vLightpos, uLightambient, uLightdiffuse, uLightspecular,
    uMatambient, uMatspecular, uMatshininess,
    vPosition, gl_FrontFacing ? vNormal : -vNormal, in_diffuse,
    ambient, diffuse, spec
  );
  $FRAG_OUT = ambient + diffuse + spec + uMatemission;
EOF
vs_out_lightgouraudstart => "  vec3 vNormal, vPosition;\n  vec4 vLightpos;\n",
vs_out_lightgouraud => <<'EOF',
  vFrontcolour = lightfuncgouraud(
    vLightpos, uLightambient, uLightdiffuse, uLightspecular,
    uMatambient, uMatspecular, uMatshininess,
    vPosition, vNormal
  ) + uMatemission;
  vBackcolour = lightfuncgouraud(
    vLightpos, uLightambient, uLightdiffuse, uLightspecular,
    uMatambient, uMatspecular, uMatshininess,
    vPosition, -vNormal
  ) + uMatemission;
EOF
fs_in_lightpos_decl => "$FS_IN vec4 vLightpos;\n",
fs_in_lightgouraud_decl => "$FS_IN vec4 vFrontcolour;\n$FS_IN vec4 vBackcolour;\n",
vs_out_lightgouraud_decl => "$VS_OUT vec4 vFrontcolour;\n$VS_OUT vec4 vBackcolour;\n",
fs_out_lightgouraud => <<EOF,
  $FRAG_OUT = (gl_FrontFacing ? vFrontcolour : vBackcolour) * in_diffuse;
EOF
u_tex_decl => "uniform sampler2D tex;\n",
u_light_decl => <<'EOF',
uniform vec4 uLightposition;
uniform vec4 uLightambient;
uniform vec4 uLightdiffuse;
uniform vec4 uLightspecular;
uniform float uMatshininess;
uniform vec4 uMatspecular;
uniform vec4 uMatambient;
uniform vec4 uMatdiffuse;
uniform vec4 uMatemission;
EOF
u_matrix_decl => <<'EOF',
uniform mat4 uMV;
uniform mat4 uMVP;
uniform mat3 uNormalMatrix;
EOF
);

{ package # hide from PAUSE
  PDL::Graphics::TriD::GObject;
use OpenGL::Modern qw(
  glLineWidth glPointSize
  glBlendFunc
  glEnable glDisable
  glGetIntegerv_p
  glGenBuffers_p glBindBuffer glDeleteBuffers_p glBufferData_c
  glGenTextures_p glBindTexture glDeleteTextures_p glIsTexture
  glTexImage2D_c glTexParameteri
  glCreateShader glDeleteShader glShaderSource_p glCompileShader
  glAttachShader glDetachShader
  glGetShaderiv_p glGetShaderInfoLog_p
  glCreateProgram glDeleteProgram glLinkProgram glUseProgram glIsProgram
  glGetProgramiv_p glGetProgramInfoLog_p
  glGetAttribLocation glEnableVertexAttribArray glDisableVertexAttribArray
  glGetUniformLocation glUniform1i glUniform1f glUniform4f
  glUniformMatrix3fv_p glUniformMatrix4fv_p
  glVertexAttribPointer_c
  GL_COMPILE_STATUS GL_LINK_STATUS GL_FALSE GL_TRUE
  GL_VERTEX_SHADER GL_FRAGMENT_SHADER GL_CURRENT_PROGRAM
  GL_DEPTH_TEST GL_BLEND GL_SRC_ALPHA GL_ONE_MINUS_SRC_ALPHA
  GL_ARRAY_BUFFER GL_ARRAY_BUFFER_BINDING
  GL_ELEMENT_ARRAY_BUFFER GL_ELEMENT_ARRAY_BUFFER_BINDING
  GL_TEXTURE_MIN_FILTER GL_TEXTURE_MAG_FILTER
  GL_LINEAR GL_CLAMP_TO_EDGE GL_TEXTURE_WRAP_S GL_TEXTURE_WRAP_T
  GL_TEXTURE_2D GL_TEXTURE_BINDING_2D
  GL_FLOAT GL_STATIC_DRAW
);
my (%TYPE2CHECKFUNC, %OBJ_CACHE) = (
  tex => \&glIsTexture,
  prog => \&glIsProgram,
);
sub cache_do {
  my ($this, $type, $key, $make) = @_;
  PDL::barf "cache_do: unknown type '$type'" unless my $check_func = $TYPE2CHECKFUNC{$type};
  my $val_ref = \$OBJ_CACHE{ref $this}{$key};
  return $$val_ref if defined $$val_ref and my $check = $check_func->($$val_ref);
  %OBJ_CACHE = () if !($check // 1); # context went away
  $$val_ref = $make->();
}
sub load_buffer {
  my ($this, $idname, $pdl, $target, $usage) = @_;
  PDL::barf ref($this)."::load_buffer: undef ndarray" if !defined $pdl;
  $target //= GL_ARRAY_BUFFER;
  $usage //= GL_STATIC_DRAW;
  my $id = $this->{Impl}{$idname} //= glGenBuffers_p(1);
  glBindBuffer($target, $id);
  # physicalise on nbytes not on second use so nbytes is correct
  glBufferData_c($target, $pdl->make_physical->nbytes, $pdl->address_data, $usage);
  $id;
}
sub load_idx_buffer {
  my ($this, $idname, $pdl, $usage) = @_;
  PDL::barf ref($this)."::load_idx_buffer: undef ndarray" if !defined $pdl;
  $this->load_buffer($idname, $pdl, GL_ELEMENT_ARRAY_BUFFER, $usage);
}
sub load_attrib {
  my ($this, $name, $pdl, $type, $usage) = @_;
  $type //= GL_FLOAT;
  PDL::barf "load_attrib: no program found" unless
    my ($program) = grep defined, @{ $this->{Impl} }{qw(program program_nodestroy)};
  PDL::barf "load_attrib: invalid name '$name'" if 0 >
    (my $loc = glGetAttribLocation($program, $name));
  my $idname = "attrib_$name";
  my $id = $this->load_buffer($idname => $pdl, undef, $usage);
  push @{ $this->{Impl}{attrib_indices} }, [ $id, $loc, $pdl->dim(0), $type ];
  $loc;
}
my %SUFFIX2FUNC = (
  '1i' => \&glUniform1i,
  '1f' => \&glUniform1f,
  '4f' => \&glUniform4f,
  'Mat3' => \&glUniformMatrix3fv_p,
  'Mat4' => \&glUniformMatrix4fv_p,
);
sub set_uniform {
  my ($this, $name, $suffix, $value) = @_;
  return if $this->{Impl}{uniform_gone}{$name}; # got elim
  PDL::barf "set_uniform: value must be array-ref" unless ref($value) eq 'ARRAY';
  PDL::barf "set_uniform: unknown suffix '$suffix'" unless $SUFFIX2FUNC{$suffix};
  PDL::barf "set_uniform: no program found" unless
    my ($program) = grep defined, @{ $this->{Impl} }{qw(program program_nodestroy)};
  if (!$this->{Impl}{uniform_indices}{$name}) {
    my $loc = glGetUniformLocation($program, $name);
    $this->{Impl}{uniform_gone}{$name} = 1, return if $loc < 0; # got elim
    $this->{Impl}{uniform_indices}{$name} = [ $loc, $suffix ];
  }
  $this->{Impl}{uniform_indices}{$name}[2] = $value;
}
sub set_uniforms {
  my ($this, $uniforms) = @_;
  $this->set_uniform($_ => @{ $uniforms->{$_} }) for sort keys %$uniforms;
}
sub load_texture {
  my ($this, $idname, $pdl, $iformat, $x, $y, $format, $type, $target) = @_;
  PDL::barf ref($this)."::load_texture: undef ndarray" if !defined $pdl;
  PDL::barf ref($this)."::load_texture: undef \$x/\$y" if grep !defined, $x, $y;
  $type //= GL_FLOAT;
  $target //= GL_TEXTURE_2D;
  if (!$this->{Impl}{$idname} or !glIsTexture($this->{Impl}{$idname})) {
    $this->{Impl}{$idname} = glGenTextures_p(1);
  }
  glBindTexture($target, $this->{Impl}{$idname});
  glTexImage2D_c($target, 0, $iformat, $x, $y, 0, $format, $type, $pdl->make_physical->address_data);
  glTexParameteri($target, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri($target, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glTexParameteri($target, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri($target, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  $this->{Impl}{$idname};
}
sub togl_bind {
  my ($this) = @_;
  # font_id doesn't get deleted in DESTROY
  if (my ($id) = grep defined, @{ $this->{Impl} }{qw(tex_id font_id)}) {
    glBindTexture(GL_TEXTURE_2D, $id);
    glEnable(GL_TEXTURE_2D);
  }
  if (defined $this->{Impl}{indx_buf}) {
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, $this->{Impl}{indx_buf}); # unbind the VAO before you unbind the Index Buffer
  }
  if (my ($program) = grep defined, @{ $this->{Impl} }{qw(program program_nodestroy)}) {
    glUseProgram($program);
  }
  if (my $attribs = $this->{Impl}{attrib_indices}) {
    glBindBuffer(GL_ARRAY_BUFFER, $_->[0]), # won't need this when VAO
      glVertexAttribPointer_c(@$_[1..3], GL_FALSE, 0, 0),
      glEnableVertexAttribArray($_->[1]) for @$attribs;
  }
  if (my $uniforms = $this->{Impl}{uniform_indices}) {
    $SUFFIX2FUNC{$_->[1]}->($_->[0], @{ $_->[2] }) for values %$uniforms;
  }
}
sub togl_unbind {
  my ($this) = @_;
  glBindBuffer($_, 0) for GL_ARRAY_BUFFER, GL_ELEMENT_ARRAY_BUFFER;
  if (defined $this->{Impl}{tex_id}) {
    glBindTexture(GL_TEXTURE_2D, 0);
    glDisable(GL_TEXTURE_2D);
  }
  glUseProgram(0) if grep defined, @{ $this->{Impl} }{qw(program program_nodestroy)};
  if (my $attribs = $this->{Impl}{attrib_indices}) {
    glDisableVertexAttribArray($_->[1]) for @$attribs;
  }
}
sub compile_shader {
  my ($this, $type, $src) = @_;
  my $shader = glCreateShader($type);
  glShaderSource_p($shader, $src);
  glCompileShader($shader);
  my $status = glGetShaderiv_p($shader, GL_COMPILE_STATUS);
  if ($status == GL_FALSE) {
    my $str = sprintf("%s shader compilation failed for:\n---8<---\n",
        $type == GL_VERTEX_SHADER ? "Vertex" : "Fragment");
    $src =~ s#\n+\z##;
    $str .= "$src\n---8<---\n";
    $str .= glGetShaderInfoLog_p($shader);
    glDeleteShader($shader);
    die $str;
  }
  $shader;
}
sub compile_program {
  my ($this, $vsrc, $fsrc, $prelink) = @_;
  my $vShader = $this->compile_shader(GL_VERTEX_SHADER, $vsrc);
  my $fShader = $fsrc && eval { $this->compile_shader(GL_FRAGMENT_SHADER, $fsrc) };
  if (my $err = $@) {
    glDeleteShader($vShader);
    die $err;
  }
  my $program = glCreateProgram();
  glAttachShader($program, $vShader);
  glAttachShader($program, $fShader) if $fsrc;
  $prelink->($program) if $prelink;
  glLinkProgram($program);
  my $status = glGetProgramiv_p($program, GL_LINK_STATUS);
  glDetachShader($program, $vShader);
  glDetachShader($program, $fShader) if $fsrc;
  glDeleteShader($vShader);
  glDeleteShader($fShader) if $fsrc;
  if ($status == GL_FALSE) {
    my $str = "Program linker failed.\n";
    $str .= glGetProgramInfoLog_p($program);
    glDeleteProgram($program);
    die $str;
  }
  $program;
}
my $vertex_shader_poscol = join '', @SHADERBITS{qw(version
  vs_in_position_decl vs_in_colour_decl vs_out_colour_decl u_matrix_decl
  main_start vs_in vs_out vs_out_colour main_end
)};
my $fragment_shader_poscol = join '', @SHADERBITS{qw(version
  fs_in_colour_decl fs_out_fragcolour_decl
  main_start fs_diffuse_colour fs_out_flat main_end
)};
sub program_poscol {
  my ($this, $points, $colours) = @_;
  $this->{Impl}{program_nodestroy} = $this->cache_do(prog => 'shader', sub {
    $this->compile_program($vertex_shader_poscol, $fragment_shader_poscol);
  });
  $this->load_attrib(position => $points);
  $this->load_attrib(colour => $colours);
}
sub togl {
  my ($this, $points, $uniforms) = @_;
  print "togl $this\n" if $PDL::Graphics::TriD::verbose;
  glLineWidth($this->{Options}{LineWidth} || 1);
  glPointSize($this->{Options}{PointSize} || 1);
  glEnable(GL_DEPTH_TEST);
  glEnable(GL_BLEND);
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
  $this->gdraw($points, $uniforms);
}
sub DESTROY {
  my ($this) = @_;
  print "DESTROY $this\n" if $PDL::Graphics::TriD::verbose;
  my @array_bufs = grep defined, @{ $this->{Impl} }{qw(vert_buf color_buf norm_buf texc_buf)};
  if (@array_bufs) {
    my $bound = glGetIntegerv_p(GL_ARRAY_BUFFER_BINDING);
    glBindBuffer(GL_ARRAY_BUFFER, 0) if grep $bound == $_, @array_bufs;
  }
  my @elt_bufs = grep defined, @{ $this->{Impl} }{qw(indx_buf)};
  if (@elt_bufs) {
    my $bound = glGetIntegerv_p(GL_ELEMENT_ARRAY_BUFFER_BINDING);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0) if grep $bound == $_, @elt_bufs;
  }
  glDeleteBuffers_p(@array_bufs, @elt_bufs) if @array_bufs + @elt_bufs;
  if (defined(my $tex_id = $this->{Impl}{tex_id})) {
    glBindTexture(GL_TEXTURE_2D, 0) if glGetIntegerv_p(GL_TEXTURE_BINDING_2D) == $tex_id;
    glDeleteTextures_p($tex_id);
  }
  if (my $program = $this->{Impl}{program}) {
    glUseProgram(0) if glGetIntegerv_p(GL_CURRENT_PROGRAM) == $program;
    glDeleteProgram($_) for grep $_, $program;
  }
}
}

{ package # hide from PAUSE
  PDL::Graphics::TriD::Labels;
use OpenGL::Modern qw(
  glDrawElements_c
  GL_TRIANGLES GL_UNSIGNED_INT
  GL_RGBA32F GL_RGBA
);
use PDL::Graphics::OpenGLQ;
my %FONT;
sub _font_setup {
  my ($fref) = @_;
  my ($texture, $rightbound, $orig) = gl_font_texture();
  $fref->{texture} = PDL::float(1,1,1,1) * $texture->dummy(0,1);
  my $widthpix = $rightbound->numdiff; $widthpix->slice('0') += 1;
  $fref->{widthflt} = $widthpix->float;
  $fref->{widthflt11} = $fref->{widthflt}->t->append([1,1])->dummy(1);
  $fref->{heightpix} = $texture->dim(1);
  $fref->{numchars} = my $numchars = $rightbound->nelem;
  my $texwidthm1 = $texture->dim(0) - 1;
  my $leftbound = $rightbound->rotate(1) + 1;
    $leftbound->slice('0') .= 0; $leftbound->set_datatype(PDL::float->enum);
  $rightbound = $rightbound->float;
  $_ /= $texwidthm1 for $leftbound, $rightbound;
  @$fref{qw(xorig yorig)} = $orig->list;
  $fref->{texture} = PDL::float(1,1,1,1) * $texture->dummy(0,1);
  # 4 = top-left, bot-left, top-right, bot-right, triangle idx=012,213
  $fref->{idx} = PDL->new(PDL::ulong, [0,1,2], [2,1,3]);
  my $texcoords = $fref->{texcoords} = PDL->zeroes(PDL::float,2,4,$numchars);
  $texcoords->slice('(0),0:1') .= $leftbound->dummy(0,1);  # u of left
  $texcoords->slice('(0),2:3') .= $rightbound->dummy(0,1); # u of right
  $texcoords->slice('(1),0::2') .= 1;          # v of top, v bot=already 0
}
my $vertex_shader = join '', @SHADERBITS{qw(version
  vs_in_position_decl vs_in_texcoord_decl vs_out_texcoord_decl u_matrix_decl
  main_start vs_in vs_out vs_out_texcoord main_end
)};
my $fragment_shader = join '', @SHADERBITS{qw(version
  fs_in_texcoord_decl fs_out_fragcolour_decl u_tex_decl
  main_start fs_diffuse_tex fs_out_flat main_end
)};
sub togl_setup {
  my ($this,$points) = @_;
  print "togl_setup $this\n" if $PDL::Graphics::TriD::verbose;
  _font_setup(\%FONT) if !keys %FONT;
  $this->{Impl}{font_id} = $this->cache_do(tex => 'tex', sub {
    $this->load_texture(font_id => $FONT{texture}, GL_RGBA32F, ($FONT{texture}->dims)[1,2], GL_RGBA);
  });
  $points //= $this->{Points}; # as Labels is used in Graph
  my $numchars = $FONT{numchars};
  my $vert_template = PDL->new(PDL::float, [0,0,1], [0,0,0], [1,0,1], [1,0,0]);
  my $dwidth = $PDL::Graphics::TriD::Window::DEFAULT_WIDTH / 1.5;
  my $dheight = $PDL::Graphics::TriD::Window::DEFAULT_HEIGHT / 1.5;
  $vert_template *= PDL::float(1 / $dwidth, 1, $FONT{heightpix} / $dheight);
  my @codes = map [map ord, split //], @{ $this->{Strings} };
  my ($v2, @v1, @v3) = PDL->null;
  for (0..$#codes) {
    my $l = $codes[$_];
    PDL::barf "Codepoint $_ >= $numchars" for grep $_ >= $numchars, @$l;
    push @v1, ($_) x @$l;
    push @v3, @$l;
    $v2 = PDL::glue(0,$v2,$FONT{widthflt}->dice_axis(0,$l)->cumusumover);
  }
  my $v = $points->dice_axis(1, \@v1)->dummy(1) +
    ($v2->t->append([0,0])->dummy(1) / $dwidth) +
    $vert_template * $FONT{widthflt11}->dice_axis(2,\@v3);
  $this->{Impl}{program_nodestroy} = $this->cache_do(prog => 'shader', sub {
    $this->compile_program($vertex_shader, $fragment_shader);
  });
  $this->load_attrib(position => $v->clump(1,2));
  $this->load_attrib(texcoord => $FONT{texcoords}->dice_axis(2,\@v3)->clump(1,2));
  $this->load_idx_buffer(indx_buf => $this->{Impl}{idx} = $FONT{idx}->flat + 4 * PDL->sequence(PDL::ulong,1,0+@v1));
  $this->togl_unbind;
}
sub gdraw {
  my ($this, $points, $uniforms) = @_;
  $this->set_uniforms($uniforms);
  $this->togl_bind;
  glDrawElements_c(GL_TRIANGLES, $this->{Impl}{idx}->nelem, GL_UNSIGNED_INT, 0);
  $this->togl_unbind;
}
}

{ package # hide from PAUSE
  PDL::Graphics::TriD::GL::Primitive;
use OpenGL::Modern qw(glDrawArrays);
sub togl_setup {
  my ($this,$points) = @_;
  $points //= $this->{Points}; # as Lines is used in Graph
  print "togl_setup $this\n" if $PDL::Graphics::TriD::verbose;
  $this->program_poscol($points, $this->{Colors});
  $this->togl_unbind;
}
sub gdraw {
  my ($this, $points, $uniforms) = @_;
  $this->set_uniforms($uniforms);
  $this->togl_bind;
  glDrawArrays($this->primitive, 0, $points->nelem / $points->dim(0));
  $this->togl_unbind;
}
}

unshift @PDL::Graphics::TriD::Points::ISA, qw(PDL::Graphics::TriD::GL::Primitive);
sub PDL::Graphics::TriD::Points::primitive {OpenGL::Modern::GL_POINTS}
unshift @PDL::Graphics::TriD::Lines::ISA, qw(PDL::Graphics::TriD::GL::Primitive);
sub PDL::Graphics::TriD::Lines::primitive {OpenGL::Modern::GL_LINES}

{ package # hide from PAUSE
  PDL::Graphics::TriD::Spheres;
use PDL::Graphics::OpenGLQ;
use OpenGL::Modern qw(
  glVertexAttribDivisor glDrawElementsInstancedARB_c
  GL_TRIANGLE_STRIP GL_UNSIGNED_INT
);
my $vertex_shader = join '', @SHADERBITS{qw(version
  vs_in_position_decl vs_in_normal_decl vs_in_offset_decl
  vs_out_lightgouraud_decl
  u_light_decl u_matrix_decl lightfunc lightfuncgouraud
  main_start vs_in vs_do_offset vs_out vs_out_lightgouraudstart vs_out_light vs_out_lightgouraud main_end
)};
my $fragment_shader = join '', @SHADERBITS{qw(version
  fs_in_lightgouraud_decl fs_out_fragcolour_decl u_light_decl
  main_start fs_diffuse_material fs_out_lightgouraud main_end
)};
my %SPHERE;
my @KEYS = qw(vertices normals idx);
sub togl_setup {
  my ($this, $points, $uniforms) = @_;
  print "togl_setup $this\n" if $PDL::Graphics::TriD::verbose;
  @SPHERE{@KEYS} = gl_sphere(0.025, 15, 15) if !keys %SPHERE;
  @{ $this->{Impl} }{@KEYS} = @SPHERE{@KEYS};
  my $need_load = !defined $this->{Impl}{program_nodestroy};
  $this->{Impl}{program_nodestroy} = $this->cache_do(prog => 'shader', sub {
    $this->compile_program($vertex_shader, $fragment_shader);
  });
  if ($need_load) {
    $this->load_attrib(position => $this->{Impl}{vertices});
    $this->load_attrib(normal => $this->{Impl}{normals});
    $this->set_uniforms($uniforms);
    $this->load_idx_buffer(indx_buf => $this->{Impl}{idx});
  }
  $this->{Impl}{offset_loc} = $this->load_attrib(offset => $points);
  $this->{Impl}{noffset} = $points->dim(1);
  $this->togl_unbind;
}
sub gdraw {
  my ($this, $points, $uniforms) = @_;
  $this->set_uniforms($uniforms);
  $this->togl_bind;
  glVertexAttribDivisor($this->{Impl}{offset_loc}, 1);
  glDrawElementsInstancedARB_c(GL_TRIANGLE_STRIP, $this->{Impl}{idx}->dim(0), GL_UNSIGNED_INT, 0, $this->{Impl}{noffset});
  glVertexAttribDivisor($this->{Impl}{offset_loc}, 0);
  $this->togl_unbind;
}
}

{ package # hide from PAUSE
  PDL::Graphics::TriD::Triangles;
use OpenGL::Modern qw(
  glBindAttribLocation
  glDrawElements_c
  GL_TRIANGLES GL_UNSIGNED_INT GL_RGB
);
my $vert_header = join '', @SHADERBITS{qw(version
  vs_in_position_decl vs_in_normal_decl vs_in_colour_decl vs_in_texcoord_decl
  vs_out_colour_decl vs_out_texcoord_decl vs_out_lightgouraud_decl
  u_light_decl u_matrix_decl lightfunc lightfuncgouraud
  main_start vs_in vs_out vs_out_colour vs_out_texcoord
)};
my %vert = (
  light => join('', $vert_header, @SHADERBITS{qw(vs_out_lightgouraudstart vs_out_light vs_out_lightgouraud main_end)}),
  flat => join('', $vert_header, @SHADERBITS{qw(main_end)}),
);
my $frag_header = join '', @SHADERBITS{qw(version
  fs_in_colour_decl fs_in_texcoord_decl fs_in_lightgouraud_decl
  fs_out_fragcolour_decl u_tex_decl
  main_start
)};
my $frag_colour = join '', @SHADERBITS{qw(fs_diffuse_colour)};
my $frag_tex = join '', @SHADERBITS{qw(fs_diffuse_tex)};
my $frag_light = join '', @SHADERBITS{qw(fs_out_lightgouraud main_end)};
my $frag_flat = join '', @SHADERBITS{qw(fs_out_flat main_end)};
my %frag = (
  colour_light => join('', $frag_header, $frag_colour, $frag_light),
  colour_flat => join('', $frag_header, $frag_colour, $frag_flat),
  tex_light => join('', $frag_header, $frag_tex, $frag_light),
  tex_flat => join('', $frag_header, $frag_tex, $frag_flat),
);
sub togl_setup {
  my ($this, $points, $uniforms) = @_;
  print "togl_setup $this\n" if $PDL::Graphics::TriD::verbose;
  my $shading = $this->{Options}{Shading};
  my $lightflat = $shading > 2 ? 'light' : 'flat';
  my $cache_key = join '_', defined $this->{Colors} ? 'colour' : 'tex', $lightflat;
  $this->{Impl}{program_nodestroy} = $this->cache_do(prog => "shader_$cache_key", sub {
    $this->compile_program($vert{$lightflat}, $frag{$cache_key}, sub {
      my ($program) = @_;
      glBindAttribLocation($program, 0, 'position'); # needed for #version 120
    });
  });
  $this->load_attrib(position => $points);
  if (defined $this->{Colors}) {
    $this->load_attrib(colour => $this->{Colors});
  } else {
    $this->load_attrib(texcoord => $this->{TexCoord});
    $this->load_texture(tex_id => $this->{TexColors}, GL_RGB, ($this->{TexColors}->dims)[1,2], GL_RGB);
    $this->set_uniform(tex => '1i' => [0]); # must be texture unit, not ID
  }
  $this->load_idx_buffer(indx_buf => $this->{Faceidx});
  if ($shading > 2) {
    $this->load_attrib(normal => $this->{Normals});
  }
  $this->set_uniforms($uniforms);
  $this->togl_unbind;
}
sub gdraw {
  my ($this, $points, $uniforms) = @_;
  $this->set_uniforms($uniforms);
  $this->togl_bind;
  glDrawElements_c(GL_TRIANGLES, $this->{Faceidx}->nelem, GL_UNSIGNED_INT, 0);
  $this->togl_unbind;
}
}

use OpenGL::Modern qw(GL_LINE_STRIP GL_LINE_LOOP);
my %mode2enum = (
  linestrip => GL_LINE_STRIP,
  lineloop => GL_LINE_LOOP,
);

{ package # hide from PAUSE
  PDL::Graphics::TriD::DrawMulti;
use OpenGL::Modern qw(glMultiDrawElements_c GL_UNSIGNED_INT);
sub togl_setup {
  my ($this,$points) = @_;
  $points //= $this->{Points}; # as Lattice is used in Graph for CylindricalEquidistantAxes
  print "togl_setup $this\n" if $PDL::Graphics::TriD::verbose;
  $this->program_poscol($points, $this->{Colors});
  $this->load_idx_buffer(indx_buf => $this->{Indices});
  $this->togl_unbind;
  $this->{Impl}{Starts4} = $this->{Starts}->indx * PDL::Core::howbig(PDL::ulong->enum); # byte offset into GPU buffer, not elements
}
sub gdraw {
  my ($this, $points, $uniforms) = @_;
  my $mode = $mode2enum{$this->{Mode}} || PDL::barf "DrawMulti unknown mode";
  $this->set_uniforms($uniforms);
  $this->togl_bind;
  # switch to glPrimitiveRestartindex when 3.1 available
  glMultiDrawElements_c($mode, $this->{Counts}->make_physical->address_data, GL_UNSIGNED_INT, $this->{Impl}{Starts4}->make_physical->address_data, $this->{Counts}->nelem);
  $this->togl_unbind;
}
}

# has a mode to face the display and take the entire window
{ package # hide from PAUSE
  PDL::Graphics::TriD::Image;
use OpenGL::Modern qw(glDrawArrays GL_TRIANGLE_STRIP GL_RGB);
my $vertex_shader = join '', @SHADERBITS{qw(version
  vs_in_position_decl vs_in_texcoord_decl vs_out_texcoord_decl u_matrix_decl
  main_start vs_in vs_out vs_out_texcoord main_end
)};
my $fragment_shader = join '', @SHADERBITS{qw(version
  fs_in_texcoord_decl fs_out_fragcolour_decl u_tex_decl
  main_start fs_diffuse_tex fs_out_flat main_end
)};
sub togl_setup {
  my ($this,$points) = @_;
  $points //= $this->{Points};
  print "togl_setup $this\n" if $PDL::Graphics::TriD::verbose;
  my ($p,$xd,$yd,$txd,$tyd) = $this->flatten(1); # do binary alignment
  # assume proportions could change each time
  my $texvert = PDL->new(PDL::float, [
    [$xd/$txd, 0],
    [$xd/$txd, $yd/$tyd],
    [0,0],
    [0, $yd/$tyd]
  ]);
  $this->{Impl}{program_nodestroy} = $this->cache_do(prog => 'shader', sub {
    $this->compile_program($vertex_shader, $fragment_shader);
  });
  $this->load_attrib(position => $points);
  $this->load_attrib(texcoord => $texvert);
  $this->load_texture(tex_id => $p, GL_RGB, $txd, $tyd, GL_RGB);
  $this->togl_unbind;
}
sub gdraw {
  my ($this, $points, $uniforms) = @_;
  PDL::barf "Need 3,4 vert"
    if grep $_->dim(1) < 4 || $_->dim(0) != 3, $points;
  if ($this->{Options}{FullScreen}) {
    my $mv = PDL::MatrixOps::identity(PDL::float(4));
    my $p = $this->ortho(0,1,0,1,-1,1);
    $uniforms = {
      uMV => [ Mat4 => [1, 1, $mv->list] ], # count, xpose, ...
      uMVP => [ Mat4 => [1, 1, ($p x $mv)->list] ], # count, xpose, ...
      uNormalMatrix => [ Mat3 => [1, 1, $mv->slice('0:2,0:2')->inv->t->list] ],
    };
  }
  $this->set_uniforms($uniforms);
  $this->togl_bind;
  glDrawArrays(GL_TRIANGLE_STRIP, 0, $points->nelem / $points->dim(0));
  $this->togl_unbind;
}
}

{
# A window with mouse control over rotation.
package # hide from PAUSE
  PDL::Graphics::TriD::Window;

use OpenGL::Modern qw/
  glpSetAutoCheckErrors
  glPixelStorei glReadPixels_c
  glClear glClearColor
  glViewport
  GL_PACK_ALIGNMENT GL_RGB GL_UNSIGNED_BYTE
  GL_COLOR_BUFFER_BIT GL_DEPTH_BUFFER_BIT
/;

use base qw/PDL::Graphics::TriD::Object/;
use fields qw/Ev Width Height Interactive _GLObject
              _ViewPorts _CurrentViewPort /;

sub gdriver {
  my($this, $options) = @_;
  print "GL gdriver...\n" if $PDL::Graphics::TriD::verbose;
  if(defined $this->{_GLObject}){
    print "WARNING: Graphics Driver already defined for this window \n";
    return;
  }
  my $window_type = $ENV{POGL_WINDOW_TYPE} || 'glfw';
  my $gl_class = $window_type =~ /x11/i ? 'PDL::Graphics::TriD::GL::GLX' :
    $window_type =~ /glut/i ? 'PDL::Graphics::TriD::GL::GLUT' :
    'PDL::Graphics::TriD::GL::GLFW';
  (my $file = $gl_class) =~ s#::#/#g; require "$file.pm";
  print "gdriver: Calling $gl_class(@$options{qw(width height)})\n" if $PDL::Graphics::TriD::verbose;
  $this->{_GLObject} = $gl_class->new($options, $this);
  $this->{_GLObject}->set_window;
  print "gdriver: Calling glClearColor...\n" if $PDL::Graphics::TriD::verbose;
  glClearColor(0,0,0,1);
  print "STARTED OPENGL!\n" if $PDL::Graphics::TriD::verbose;
  if($PDL::Graphics::TriD::offline) {
    $this->doconfig($options->{width}, $options->{height});
  }
  return 1;  # Interactive Window
}

sub reshape {
	my($this,$x,$y) = @_;
	my $pw = $this->{Width};
	my $ph = $this->{Height};
	$this->{Width} = $x; $this->{Height} = $y;
	for my $vp (@{$this->{_ViewPorts}}){
	  my $nw = $vp->{W} + ($x-$pw) * $vp->{W}/$pw;
	  my $nx0 = $vp->{X0} + ($x-$pw) * $vp->{X0}/$pw;
	  my $nh = $vp->{H} + ($y-$ph) * $vp->{H}/$ph;
	  my $ny0 = $vp->{Y0} + ($y-$ph) * $vp->{Y0}/$ph;
	  print "reshape: resizing viewport to $nx0,$ny0,$nw,$nh\n" if($PDL::Graphics::TriD::verbose);
	  $vp->resize($nx0,$ny0,$nw,$nh);
	  $vp->{Impl}{highlight}{IsValid} = 0;
	}
}

sub twiddle {
  my($this,$getout,$dontshow) = @_;
  my (@e);
  my $quit;
  if ($PDL::Graphics::TriD::offline) {
    $PDL::Graphics::TriD::offlineindex ++;
    $this->display();
    require PDL::IO::Pic;
    wpic($this->read_picture(),"PDL_$PDL::Graphics::TriD::offlineindex.jpg");
    return;
  }
  return if $getout and $dontshow and !$this->{_GLObject}->event_pending;
  $getout //= !($PDL::Graphics::TriD::keeptwiddling && $PDL::Graphics::TriD::keeptwiddling);
  $this->display();
  TWIDLOOP: while(1) {
    print "EVENT!\n" if $PDL::Graphics::TriD::verbose;
    my $hap = 0;
    my $gotev = 0;
    if ($this->{_GLObject}->event_pending or !$getout) {
      @e = $this->{_GLObject}->next_event;
      $gotev=1;
    }
    print "e= ".join(",",$e[0]//'undef',@e[1..$#e])."\n" if $PDL::Graphics::TriD::verbose;
    if (@e and defined $e[0]) {
      if ($e[0] eq 'visible') {
        $hap = 1;
      } elsif ($e[0] eq 'reshape') {
        print "CONFIGNOTIFE\n" if $PDL::Graphics::TriD::verbose;
        $this->reshape(@e[1,2]);
        $hap=1;
      } elsif ($e[0] eq 'destroy') {
        print "DESTROYNOTIFE\n" if $PDL::Graphics::TriD::verbose;
        $quit = 1;
        $hap=1;
        $this->close;
        last TWIDLOOP;
      } elsif ($e[0] eq 'keypress') {
        print "KEYPRESS: '$e[1]'\n" if $PDL::Graphics::TriD::verbose;
        if (lc($e[1]) eq "q") {
          $quit = 1;
          last TWIDLOOP if not $getout;
        }
        if (lc($e[1]) eq "c") {
          $quit = 2;
        }
        $hap=1;
      }
    }
    if ($gotev) {
      foreach my $vp (@{$this->{_ViewPorts}}) {
        if (defined($vp->{EHandler})) {
          $hap += $vp->{EHandler}->event(@e) || 0;
        }
      }
    }
    if (!$this->{_GLObject}->event_pending) {
           $this->display if $hap;
           last TWIDLOOP if $getout;
    }
    @e = ();
  }
  print "STOPTWIDDLE\n" if $PDL::Graphics::TriD::verbose;
  return $quit;
}

sub close {
  my ($this, $close_window) = @_;
  print "CLOSE\n" if $PDL::Graphics::TriD::verbose;
  undef $this->{_GLObject};
  $PDL::Graphics::TriD::current_window = undef;
}

use constant { PI => 3.1415926535897932384626433832795, FOVY => 40.0,
  zNEAR => 0.1, zFAR => 200.0 };
use constant ANGLE => FOVY / 360 * PI;
use constant TAN => sin(ANGLE)/cos(ANGLE);
use constant fH => TAN * zNEAR;
sub display {
  my ($this) = @_;
  return if !defined($this) or !defined $this->{_GLObject}; # eg global destroy
  $this->{_GLObject}->set_window; # for multiwindow support
  print "display: calling glClear()\n" if $PDL::Graphics::TriD::verbose;
  glClear(GL_COLOR_BUFFER_BIT|GL_DEPTH_BUFFER_BIT);
  for my $vp (@{$this->{_ViewPorts}}) {
    print "VALID $this=$this->{IsValid}\n" if $PDL::Graphics::TriD::verbose;
    if (!$vp->{IsValid}) {
      glpSetAutoCheckErrors(1);
      $vp->togl_setup(undef, {
        uLightposition => ['4f' => [1,1,1,0]],
        uLightambient => ['4f' => [0,0,0,1]],
        uLightdiffuse => ['4f' => [1,1,1,1]],
        uLightspecular => ['4f' => [1,1,1,1]],
        %{$vp->{DefMaterial}->to_uniforms},
      });
      print "VALID1 $vp\n" if $PDL::Graphics::TriD::verbose;
      $vp->{IsValid} = 1;
    }
    PDL::barf "Need viewport with positive dims, got $vp->{W},$vp->{H}" if !($vp->{W}>0 and $vp->{H}>0);
    glViewport(@$vp{qw(X0 Y0 W H)});
    $vp->highlight if $vp->{Active};
    my $tr = $vp->transformer;
    my $r1 = $tr->{CRotation}->as_matrix;
    my $t1 = $this->translate(0,0,-$tr->{CDistance});
    my $r2 = $tr->{WRotation}->as_matrix;
    my $t2 = $this->translate(map -$_, @{$tr->{WOrigin}});
    my $mv = $r1 x $t1 x $r2 x $t2;
    my $fW = fH * $vp->{W}/$vp->{H}; # aspect ratio
    my $p = $this->frustum(-$fW, $fW, -fH, fH, zNEAR, zFAR);
    $vp->togl({
      uMV => [ Mat4 => [1, 1, $mv->list] ], # count, xpose, ...
      uMVP => [ Mat4 => [1, 1, ($p x $mv)->list] ], # count, xpose, ...
      uNormalMatrix => [ Mat3 => [1, 1, $mv->slice('0:2,0:2')->inv->t->list] ],
    });
  }
  $this->{_GLObject}->swap_buffers;
  print "display: after SwapBuffers\n" if $PDL::Graphics::TriD::verbose;
}

# should this really be in viewport?
sub read_picture {
  my ($this) = @_;
  my ($w,$h) = @{$this}{qw/Width Height/};
  my $res = PDL->zeroes(PDL::byte,3,$w,$h);
  glPixelStorei(GL_PACK_ALIGNMENT,1);
  glReadPixels_c(0,0,$w,$h,GL_RGB,GL_UNSIGNED_BYTE,$res->make_physical->address_data);
  return $res;
}
}

{
package # hide from PAUSE
  PDL::Graphics::TriD::ViewPort;
unshift @PDL::Graphics::TriD::GL::Highlight::ISA, qw(PDL::Graphics::TriD::Lines);
sub PDL::Graphics::TriD::GL::Highlight::primitive {OpenGL::Modern::GL_LINE_LOOP}
sub highlight {
  my ($vp) = @_;
  my $hl = $vp->{Impl}{highlight} //= PDL::Graphics::TriD::GL::Highlight->new(
    PDL->zeroes(PDL::float, 2, 4),
    PDL->new(PDL::float, [1,1,1]),
    { LineWidth => 4 },
  );
  my ($w, $h) = @$vp{qw(W H)};
  if (!$hl->{IsValid}) {
    $hl->{Points} .= PDL->new(PDL::float, [[0,0], [$w,0], [$w,$h], [0,$h]]),
    $hl->togl_setup;
    $hl->{IsValid} = 1;
  }
  my $mv = PDL::MatrixOps::identity(PDL::float(4));
  my $p = $vp->ortho(0,$w,0,$h,-1,1);
  $hl->togl($hl->{Points}, {
    uMV => [ Mat4 => [1, 1, $mv->list] ], # count, xpose, ...
    uMVP => [ Mat4 => [1, 1, ($p x $mv)->list] ], # count, xpose, ...
    uNormalMatrix => [ Mat3 => [1, 1, $mv->slice('0:2,0:2')->inv->t->list] ],
  });
}
}

=head1 NAME

PDL::Graphics::TriD::GL - PDL TriD OpenGL interface using POGL

=head1 DESCRIPTION

This module provides the glue between the Perl
OpenGL functions and the API defined by the internal
PDL::Graphics::OpenGL one. It also supports any
miscellaneous OpenGL or GUI related functionality to
support PDL::Graphics::TriD refactoring.

It defines an interface that subclasses will conform to, implementing
support for GLFW, GLUT, X11+GLX, etc, as the mechanism for creating windows
and graphics contexts.

=head1 CONFIG

Defaults to using L<OpenGL::GLFW> - override by setting the environment
variable C<POGL_WINDOW_TYPE> to C<glut>, C<x11> , or the default is C<glfw>.

=head2 new

=for ref

Returns a new OpenGL object.

=for usage

  new($class,$options,[$window_type])

  Attributes are specified in the $options field; the 3d $window_type is optionsl. The attributes are:

=over

=item x,y - the position of the upper left corner of the window (0,0)

=item width,height - the width and height of the window in pixels (500,500)

=back

Allowed 3d window types, case insensitive, are:

=over

=item glfw - use Perl OpenGL bindings and GLFW windows (no Tk)

=item glut - use Perl OpenGL bindings and GLUT windows (no Tk)

=item x11  - use Perl OpenGL (POGL) bindings with X11

Additional attributes for X11 windows:

=over

=item parent - the parent under which the new window should be opened (root)

=item mask - the user interface mask (StructureNotifyMask)

=item attributes - attributes to pass to glXChooseVisual

=back

=back

=cut

sub new {
  my($class,$options,$window_obj) = @_;
  my $opt = PDL::Options->new($class->default_options);
  $opt->incremental(1);
  $opt->options($options) if(defined $options);
  my $p = $opt->options;
  bless {Options => $p}, ref($class)||$class;
}

=head2 default_options

default options for object oriented methods

=cut

sub default_options {
  {
    x => 0,
    y => 0,
    width => 500,
    height => 500,
  }
}

=head2 swap_buffers

OO interface to swapping frame buffers

=cut

sub swap_buffers {
  my ($this) = @_;
  die "swap_buffers: got object with inconsistent _GLObject info\n";
}

=head2 set_window

OO interface to setting the display window (if appropriate)

=cut

sub set_window {
  my ($this) = @_;
}

=head1 AUTHOR

Chris Marshall, C<< <devel dot chm dot 01 at gmail.com> >>

=head1 BUGS

Bugs and feature requests may be submitted through the PDL GitHub
project page at L<https://github.com/PDLPorters/pdl/issues> .

=head1 SUPPORT

PDL uses a mailing list support model.  The Perldl mailing list
is the best for questions, problems, and feature discussions with
other PDL users and PDL developers.

To subscribe see the page at L<http://pdl.perl.org/?page=mailing-lists>

=head1 ACKNOWLEDGEMENTS

TBD including PDL TriD developers and POGL developers...thanks to all.

=head1 COPYRIGHT & LICENSE

Copyright 2009 Chris Marshall.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.

=cut

1;
