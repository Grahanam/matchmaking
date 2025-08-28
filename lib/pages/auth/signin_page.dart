import "package:app/bloc/auth/auth_bloc.dart";
import "package:app/pages/auth/signup_page.dart";
import "package:app/pages/home/home.dart";
import "package:app/pages/layout/main_layout.dart";
import "package:email_validator/email_validator.dart";
import "package:flutter/material.dart";
import "package:flutter_bloc/flutter_bloc.dart";

class SignIn extends StatefulWidget {
  const SignIn({super.key});

  @override
  State<SignIn> createState() => _SignInState();
}

class _SignInState extends State<SignIn> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
    bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // appBar: AppBar(
      //   title: const Text("SignIn"),
      // ),
      body: BlocListener<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is Authenticated) {
            // Navigating to the dashboard screen if the user is authenticated
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const MainLayout()),
            );
          }
          if (state is AuthError) {
            // Showing the error message if the user has entered invalid credentials
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(state.error)));
          }
        },
        child: BlocBuilder<AuthBloc, AuthState>(
          builder: (context, state) {
            if (state is Loading) {
              // Showing the loading indicator while the user is signing i
              return const Center(child: CircularProgressIndicator());
            }
            if (state is UnAuthenticated) {
              // Showing the sign in form if the user is not authenticated
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(18.0),
                  child: SingleChildScrollView(
                    reverse: true,
                    child: Column(
                      // crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          "Sign In",
                          style: TextStyle(
                            fontSize: 38,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Center(
                          child: Form(
                            key: _formKey,
                            child: Container(
                              //  padding: const EdgeInsets.symmetric(vertical: tFormHeight - 10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  TextFormField(
                                    keyboardType: TextInputType.emailAddress,
                                    controller: _emailController,
                                    decoration: const InputDecoration(
                                      prefixIcon: Icon(
                                        Icons.person_outline_outlined,
                                      ),
                                      labelText: "Email",
                                      hintText: "Email",
                                      border: OutlineInputBorder(),
                                    ),
                                    autovalidateMode:
                                        AutovalidateMode.onUserInteraction,
                                    validator: (value) {
                                      return value != null &&
                                              !EmailValidator.validate(value)
                                          ? 'Enter a valid email'
                                          : null;
                                    },
                                  ),
                                  const SizedBox(height: 10),
                                  TextFormField(
                                    keyboardType: TextInputType.text,
                                    obscureText: _obscurePassword,
                                    controller: _passwordController,
                                    decoration: InputDecoration(
                                      prefixIcon: Icon(Icons.fingerprint),
                                      labelText: "Password",
                                      hintText: "Password",
                                      border: OutlineInputBorder(),
                                      suffixIcon: IconButton(
                                        onPressed: (){
                                          setState(() {
                                            _obscurePassword = !_obscurePassword;
                                          });
                                        },
                                        icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                ),
                                      ),
                                    ),
                                    autovalidateMode:
                                        AutovalidateMode.onUserInteraction,
                                    validator: (value) {
                                      return value != null && value.length < 6
                                          ? "Enter min. 6 characters"
                                          : null;
                                    },
                                  ),
                                  const SizedBox(height: 12),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      onPressed: () {},
                                      child: const Text("ForgetPassword ?"),
                                    ),
                                  ),
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton(
                                      onPressed: () {
                                        _authenticateWithEmailAndPassword(
                                          context,
                                        );
                                      },
                                      child: Text("login".toUpperCase()),
                                    ),
                                  ),
                                  const SizedBox(height: 10),

                                  Center(child: const Text("OR")),
                                  const SizedBox(height: 5),
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton.icon(
                                      icon: Image.asset(
                                        "assets/google.png",
                                        height: 30,
                                        width: 30,
                                      ),
                                      onPressed: () {
                                        _authenticateWithGoogle(
                                          context,
                                        );
                                      },
                                      label: const Text("Continue with Google"),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 10),
                        
                        const SizedBox(height: 10),

                        TextButton(
                          onPressed: () {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const SignUp(),
                              ),
                            );
                          },
                          child: Text.rich(
                            TextSpan(
                              text: "Don't Have An Account? ",
                              // style: Theme.of(context).textTheme.bodyText1,
                              children: const [
                                TextSpan(
                                  text: "SignUp",
                                  style: TextStyle(color: Colors.blue),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // const Text("Don't have an account?"),

                        // const SizedBox(height: 10),
                        // OutlinedButton(
                        //   onPressed: () {
                        //     Navigator.pushReplacement(
                        //       context,
                        //       MaterialPageRoute(
                        //         builder: (context) => const SignUp(),
                        //       ),
                        //     );
                        //   },
                        //   child: const Text("Sign Up"),
                        // ),
                      ],
                    ),
                  ),
                ),
              );
            }
            return Container();
          },
        ),
      ),
    );
  }

  void _authenticateWithEmailAndPassword(context) {
    if (_formKey.currentState!.validate()) {
      BlocProvider.of<AuthBloc>(
        context,
      ).add(SignInRequested(_emailController.text, _passwordController.text));
    }
  }

  void _authenticateWithGoogle(context) {
    BlocProvider.of<AuthBloc>(context).add(GoogleSignInRequested());
  }
}
